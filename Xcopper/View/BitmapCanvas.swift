import SwiftUI

@MainActor
struct BitmapCanvas<Key: Equatable>: View {
	var key: Key
	var size: Size
	var viewport: Viewport
	var isMoving: Bool
	var render: (GraphicsContext, CGFloat, CGRect) -> Void
	var overlay: (GraphicsContext) -> Void

	@Environment(\.displayScale) private var displayScale
	@Environment(\.colorScheme) private var colorScheme
	@State private var cache = BoardBitmapCache()

	private struct Request: Equatable {
		var key: Key
		var size: Size
		var scale: CGFloat
		var displayScale: CGFloat
		var colorScheme: ColorScheme
	}

	var body: some View {
		let request = Request(
			key: key,
			size: size,
			scale: viewport.magnification,
			displayScale: displayScale,
			colorScheme: colorScheme
		)
		let snapshot = cache.snapshot
		GeometryReader { geo in
			let visible = viewport.visibleRect(in: geo.size)
				.insetBy(dx: -128, dy: -128)
				.intersection(CGRect(origin: .zero, size: geo.size))
			if !visible.isNull, !visible.isEmpty {
				Canvas { context, _ in
					snapshot?.draw(in: context, scale: request.scale, visible: visible)
					overlay(modifying(context) { context in
						context.translateBy(x: -visible.minX, y: -visible.minY)
					})
				}
				.id(snapshot?.generation)
				.frame(width: visible.width, height: visible.height)
				.offset(x: visible.minX, y: visible.minY)
				.allowsHitTesting(false)
			}
		}
		.onChange(of: request, initial: true) { _, new in
			cache.update(
				size: Layout.contentSize(new.size, scale: new.scale),
				scale: new.scale,
				displayScale: new.displayScale,
				colorScheme: new.colorScheme,
				paused: isMoving,
				render: render
			)
		}
		.onChange(of: isMoving) { _, new in cache.setPaused(new) }
		.onDisappear { cache.cancel() }
	}
}

@MainActor
@Observable
private final class BoardBitmapCache {
	private struct Request {
		var generation: Int
		var size: CGSize
		var scale: CGFloat
		var displayScale: CGFloat
		var colorScheme: ColorScheme
		var render: (GraphicsContext, CGFloat, CGRect) -> Void
	}

	struct Snapshot {
		var generation: Int
		var image: CGImage
		var size: CGSize
		var scale: CGFloat

		func draw(in context: GraphicsContext, scale: CGFloat, visible: CGRect) {
			let ratio = scale / self.scale
			let origin = CGPoint(
				x: Layout.margin * (1 - ratio) - visible.minX,
				y: Layout.margin * (1 - ratio) - visible.minY
			)
			context.draw(
				Image(decorative: image, scale: 1).interpolation(.none),
				in: CGRect(origin: origin, size: size * ratio)
			)
		}
	}

	private(set) var snapshot: Snapshot?
	@ObservationIgnored private var generation = 0
	@ObservationIgnored private var pending: Request?
	@ObservationIgnored private var worker: Task<Void, Never>?
	@ObservationIgnored private var paused = false
	@ObservationIgnored private var buffers: [BoardBitmapBuffer] = []
	@ObservationIgnored private var front = 1

	func update(
		size: CGSize,
		scale: CGFloat,
		displayScale: CGFloat,
		colorScheme: ColorScheme,
		paused: Bool,
		render: @escaping (GraphicsContext, CGFloat, CGRect) -> Void
	) {
		generation &+= 1
		pending = Request(
			generation: generation,
			size: size,
			scale: scale,
			displayScale: displayScale,
			colorScheme: colorScheme,
			render: render
		)
		setPaused(paused)
	}

	func setPaused(_ paused: Bool) {
		self.paused = paused
		start()
	}

	private func start() {
		guard !paused, pending != nil, worker == nil else { return }
		worker = Task { await run() }
	}

	func cancel() {
		generation &+= 1
		pending = nil
		worker?.cancel()
	}

	private func run() async {
		while !Task.isCancelled, !paused, let request = pending {
			let back = 1 - front
			if buffers.isEmpty { buffers = [BoardBitmapBuffer(), BoardBitmapBuffer()] }
			let buffer = buffers[back]
			guard buffer.isAvailable else {
				do { try await Task.sleep(for: .milliseconds(16)) }
				catch { break }
				continue
			}
			pending = nil
			guard let dimensions = BoardBitmapBuffer.Dimensions(size: request.size, scale: request.displayScale),
				let image = render(request, into: buffer, dimensions: dimensions)
			else { continue }
			guard !Task.isCancelled, request.generation == generation else { continue }
			guard !paused else {
				pending = request
				continue
			}
			snapshot = Snapshot(
				generation: request.generation,
				image: image,
				size: dimensions.size,
				scale: request.scale
			)
			front = back
		}
		worker = nil
		start()
	}

	private func render(
		_ request: Request,
		into buffer: BoardBitmapBuffer,
		dimensions: BoardBitmapBuffer.Dimensions
	) -> CGImage? {
		let renderer = ImageRenderer(content:
			Canvas { context, size in
				context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.background))
				var context = context
				context.scaleBy(x: dimensions.scale, y: dimensions.scale)
				request.render(context, request.scale, CGRect(origin: .zero, size: request.size))
			}
			.frame(width: CGFloat(dimensions.width), height: CGFloat(dimensions.height))
			.environment(\.displayScale, request.displayScale)
			.environment(\.colorScheme, request.colorScheme)
		)
		var image: CGImage?
		renderer.render { _, draw in
			image = buffer.render(dimensions: dimensions, draw: draw)
		}
		return image
	}
}

private final class BoardBitmapBuffer: @unchecked Sendable {
	private static let capacity = 16 * 1_024 * 1_024
	private static let colorSpace = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)!
	private static let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
	private let data = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 64)
	private let lock = NSLock()
	private var inUse = false

	var isAvailable: Bool { lock.withLock { !inUse } }

	struct Dimensions: Sendable {
		var width: Int
		var height: Int
		var bytesPerRow: Int
		var scale: CGFloat

		var size: CGSize { CGSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale) }

		init?(size: CGSize, scale: CGFloat) {
			guard size.width.isFinite, size.height.isFinite, scale.isFinite,
				size.width > 0, size.height > 0, scale > 0
			else { return nil }
			let pixels = CGFloat(BoardBitmapBuffer.capacity)
			let scale = min(scale, sqrt(pixels / (size.width * size.height)), 16_384 / max(size.width, size.height))
			width = max(1, Int(ceil(size.width * scale)))
			bytesPerRow = (width + 63) / 64 * 64
			height = max(1, min(Int(ceil(size.height * scale)), BoardBitmapBuffer.capacity / bytesPerRow))
			self.scale = min(scale, CGFloat(height) / size.height)
		}
	}

	deinit { data.deallocate() }

	private func release() { lock.withLock { inUse = false } }

	func render(dimensions: Dimensions, draw: (CGContext) -> Void) -> CGImage? {
		guard lock.withLock({
			guard !inUse else { return false }
			inUse = true
			return true
		}) else { return nil }
		var transferred = false
		defer { if !transferred { release() } }
		guard let context = CGContext(
			data: data,
			width: dimensions.width,
			height: dimensions.height,
			bitsPerComponent: 8,
			bytesPerRow: dimensions.bytesPerRow,
			space: Self.colorSpace,
			bitmapInfo: Self.bitmapInfo.rawValue
		)
		else { return nil }
		context.clear(CGRect(x: 0, y: 0, width: dimensions.width, height: dimensions.height))
		draw(context)
		context.flush()
		let retained = Unmanaged.passRetained(self)
		guard let pixels = CGDataProvider(
			dataInfo: retained.toOpaque(),
			data: data,
			size: dimensions.bytesPerRow * dimensions.height,
			releaseData: { info, _, _ in
				guard let info else { return }
				let buffer = Unmanaged<BoardBitmapBuffer>.fromOpaque(info).takeRetainedValue()
				buffer.release()
			}
		) else {
			retained.release()
			return nil
		}
		transferred = true
		return CGImage(
			width: dimensions.width,
			height: dimensions.height,
			bitsPerComponent: 8,
			bitsPerPixel: 8,
			bytesPerRow: dimensions.bytesPerRow,
			space: Self.colorSpace,
			bitmapInfo: Self.bitmapInfo,
			provider: pixels,
			decode: nil,
			shouldInterpolate: false,
			intent: .defaultIntent
		)
	}
}
