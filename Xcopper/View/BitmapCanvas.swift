import AppKit
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
		GeometryReader { geo in
			let visible = viewport.visibleRect(in: geo.size)
				.insetBy(dx: -128, dy: -128)
				.intersection(CGRect(origin: .zero, size: geo.size))
			if !visible.isNull, !visible.isEmpty {
				ZStack(alignment: .topLeading) {
					BoardBitmapView(cache: cache, revision: cache.revision, scale: request.scale, visible: visible)
					Canvas { context, _ in
						var context = context
						context.translateBy(x: -visible.minX, y: -visible.minY)
						overlay(context)
					}
				}
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

	private struct Snapshot {
		var image: CGImage
		var size: CGSize
		var scale: CGFloat
	}

	private(set) var revision = 0
	@ObservationIgnored private var generation = 0
	@ObservationIgnored private var pending: Request?
	@ObservationIgnored private var worker: Task<Void, Never>?
	@ObservationIgnored private var paused = false
	@ObservationIgnored private var buffers: [BoardBitmapBuffer] = []
	@ObservationIgnored private var front = 1
	@ObservationIgnored private var snapshot: Snapshot?

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

	func draw(in context: CGContext, scale: CGFloat, visible: CGRect) {
		guard let snapshot else { return }
		let ratio = scale / snapshot.scale
		let origin = CGPoint(
			x: Layout.margin * (1 - ratio) - visible.minX,
			y: Layout.margin * (1 - ratio) - visible.minY
		)
		let size = snapshot.size * ratio
		context.saveGState()
		context.interpolationQuality = .none
		context.translateBy(x: origin.x, y: origin.y + size.height)
		context.scaleBy(x: 1, y: -1)
		context.draw(snapshot.image, in: CGRect(origin: .zero, size: size))
		context.restoreGState()
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
				let pdf = record(request, dimensions: dimensions)
			else { continue }
			let image = await Task.detached(priority: .userInitiated) {
				buffer.render(pdf, dimensions: dimensions)
			}.value
			guard !Task.isCancelled, request.generation == generation, let image else { continue }
			guard !paused else {
				pending = request
				continue
			}
			snapshot = Snapshot(image: image, size: dimensions.size, scale: request.scale)
			front = back
			revision &+= 1
		}
		worker = nil
		start()
	}

	private func record(_ request: Request, dimensions: BoardBitmapBuffer.Dimensions) -> Data? {
		let data = NSMutableData()
		var bounds = CGRect(x: 0, y: 0, width: dimensions.width, height: dimensions.height)
		guard let consumer = CGDataConsumer(data: data),
			let context = CGContext(consumer: consumer, mediaBox: &bounds, nil)
		else { return nil }
		let renderer = ImageRenderer(content:
			Canvas { context, size in
				context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.background))
				var context = context
				context.scaleBy(x: dimensions.scale, y: dimensions.scale)
				request.render(context, request.scale, CGRect(origin: .zero, size: request.size))
			}
			.frame(width: bounds.width, height: bounds.height)
			.environment(\.displayScale, request.displayScale)
			.environment(\.colorScheme, request.colorScheme)
		)
		renderer.render { _, draw in
			context.beginPDFPage(nil)
			draw(context)
			context.endPDFPage()
		}
		context.closePDF()
		return Data(referencing: data)
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

	func render(_ pdf: Data, dimensions: Dimensions) -> CGImage? {
		guard lock.withLock({
			guard !inUse else { return false }
			inUse = true
			return true
		}) else { return nil }
		var transferred = false
		defer { if !transferred { release() } }
		guard let provider = CGDataProvider(data: pdf as CFData),
			let document = CGPDFDocument(provider), let page = document.page(at: 1),
			let context = CGContext(
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
		context.drawPDFPage(page)
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

private struct BoardBitmapView: NSViewRepresentable {
	var cache: BoardBitmapCache
	var revision: Int
	var scale: CGFloat
	var visible: CGRect

	func makeNSView(context: Context) -> BitmapView {
		let view = BitmapView()
		view.wantsLayer = true
		view.layer?.magnificationFilter = .nearest
		view.layer?.minificationFilter = .nearest
		return view
	}

	func updateNSView(_ view: BitmapView, context: Context) {
		guard view.cache !== cache || view.revision != revision || view.scale != scale || view.visible != visible else { return }
		view.cache = cache
		view.revision = revision
		view.scale = scale
		view.visible = visible
		view.needsDisplay = true
	}

	final class BitmapView: NSView {
		var cache: BoardBitmapCache?
		var revision = -1
		var scale: CGFloat = 1
		var visible: CGRect = .zero

		override var isFlipped: Bool { true }

		override func draw(_ dirtyRect: NSRect) {
			guard let context = NSGraphicsContext.current?.cgContext else { return }
			context.clear(dirtyRect)
			cache?.draw(in: context, scale: scale, visible: visible)
		}
	}
}
