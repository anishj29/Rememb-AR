import SwiftUI
import RealityKit
import ARKit
import Combine

// MARK: - Notifications from SwiftUI → AR coordinator
extension Notification.Name {
    static let toggleMesh   = Notification.Name("toggleMesh")
    static let clearGarden  = Notification.Name("clearGarden")
    static let scatterNow   = Notification.Name("scatterNow")   // payload: Int (how many)
    static let flowerTapped = Notification.Name("flowerTapped") // AR → SwiftUI
}

struct ContentView: View {
    @State private var showHello = false
    @State private var meshOn = false
    @State private var showPopup = false

    var body: some View {
        ZStack {
            ARViewContainer().ignoresSafeArea()
            
            if showPopup {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation { showPopup = false } }

                    VStack {
                        Image("IMG_0832")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 300)
                            .cornerRadius(16)
                            .shadow(radius: 10)
                            .padding()

                        Button("Close") {
                            withAnimation { showPopup = false }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .transition(.scale.combined(with: .opacity))
                }

            VStack(spacing: 12) {
                Text("Scan slowly.\nTap a flower → popup")
                    .multilineTextAlignment(.center)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())

                HStack(spacing: 8) {
                    Button(meshOn ? "Hide Mesh" : "Show Mesh") {
                        meshOn.toggle()
                        NotificationCenter.default.post(name: .toggleMesh, object: meshOn)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Scatter +5") {
                        NotificationCenter.default.post(name: .scatterNow, object: 5)
                    }
                    .buttonStyle(.bordered)

                    Button("Clear") {
                        NotificationCenter.default.post(name: .clearGarden, object: nil)
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()
            }
            .padding(.top, 16)
            .padding(.horizontal, 12)
        }
        .onReceive(NotificationCenter.default.publisher(for: .flowerTapped)) { _ in
            withAnimation(.spring()) {
                showPopup = true
            }
        }
    }
}

// MARK: - AR container
struct ARViewContainer: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // AR config (LiDAR mesh if available)
        let cfg = ARWorldTrackingConfiguration()
        cfg.planeDetection = [.horizontal, .vertical]
        cfg.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            cfg.sceneReconstruction = .meshWithClassification
        } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            cfg.sceneReconstruction = .mesh
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            cfg.frameSemantics.insert(.sceneDepth)
        }
        arView.session.run(cfg, options: [.resetTracking, .removeExistingAnchors])

        // Use real mesh for occlusion + physics
        arView.environment.sceneUnderstanding.options.insert(.occlusion)
        arView.environment.sceneUnderstanding.options.insert(.physics)

        // Coaching
        let coach = ARCoachingOverlayView()
        coach.session = arView.session
        coach.goal = .horizontalPlane
        coach.translatesAutoresizingMaskIntoConstraints = false
        arView.addSubview(coach)
        NSLayoutConstraint.activate([
            coach.topAnchor.constraint(equalTo: arView.topAnchor),
            coach.bottomAnchor.constraint(equalTo: arView.bottomAnchor),
            coach.leadingAnchor.constraint(equalTo: arView.leadingAnchor),
            coach.trailingAnchor.constraint(equalTo: arView.trailingAnchor)
        ])

        // Coordinator + gestures
        context.coordinator.arView = arView
        arView.session.delegate = context.coordinator
        context.coordinator.bindUI()

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tap)

        // Auto-scatter ONCE when tracking stabilizes (only 10)
        context.coordinator.startAutoScatterOnce(targetCount: 10)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    // MARK: - Coordinator
    class Coordinator: NSObject, ARSessionDelegate {
        weak var arView: ARView?

        private let flowerUSDZName = "Flower.usdz"
        private var flowerCachedOriginal: ModelEntity?
        private var hasAutoScattered = false
        private var gardenAnchors: [AnchorEntity] = []

        // NEW: monitoring
        private var lastFlowerVisibleTime: Date = .now
        private var visibilityTimer: Timer?

        // Load once, then clone for each placement
        private func loadFlowerModel() -> ModelEntity {
            if let cached = flowerCachedOriginal {
                return cached.clone(recursive: true)
            }

            if let model = try? Entity.loadModel(named: flowerUSDZName) as? ModelEntity {
                flowerCachedOriginal = model
                return model.clone(recursive: true)
            } else {
                // Fallback to the procedural flower if the asset isn’t in the bundle
                return makeProceduralFlower()
            }
        }

        // Make the model feel “right” in AR: fix base to ground, normalize size, add shadow
        private func normalizeAndGround(_ entity: ModelEntity, targetHeight: Float = 0.15) {
            // 1) Normalize height (so different assets feel consistent)
            let bounds = entity.visualBounds(relativeTo: nil)
            let currentHeight = max(0.001, bounds.extents.y)
            let scaleFactor = targetHeight / currentHeight
            entity.scale *= scaleFactor

            // 2) Snap base to y=0 (so it sits on the surface)
            let newBounds = entity.visualBounds(relativeTo: nil)
            let lift = -newBounds.min.y
            entity.position.y += lift

            // 3) Add a subtle shadow blob for grounding
            let shadowSize = max(0.12, min(0.25, targetHeight * 0.9))
            var shadowMat = UnlitMaterial()
            shadowMat.color = .init(tint: UIColor(white: 0, alpha: 0.15))
            let shadow = ModelEntity(
                mesh: .generatePlane(width: shadowSize, depth: shadowSize),
                materials: [shadowMat]
            )
            shadow.orientation = simd_quatf(angle: -.pi/2, axis: [1,0,0])
            shadow.position.y = 0.001
            entity.addChild(shadow)
        }

        private func plantFlower(at transform: float4x4) {
            guard let arView else { return }
            let anchor = AnchorEntity(world: transform)

            // Load USDZ or fallback
            let flower = loadFlowerModel()
            // Normalize + ground to surface
            let randomHeight: Float = Float.random(in: 0.13...0.18)
            normalizeAndGround(flower, targetHeight: randomHeight)

            let widthScale: Float = Float.random(in: 0.9...1.1)
            flower.scale.x *= widthScale
            flower.scale.z *= widthScale
            
            // (Optional) slight randomization so a cluster looks natural
            flower.orientation *= simd_quatf(angle: Float.random(in: -0.25...0.25), axis: [0,1,0])
            flower.scale *= Float.random(in: 0.9...1.15)

            // Keep it static (no falling)
            let physMat = PhysicsMaterialResource.generate(friction: 0.9, restitution: 0.05)
            let body = PhysicsBodyComponent(massProperties: .default, material: physMat, mode: .static)
            flower.components.set(body)
            flower.generateCollisionShapes(recursive: true)

            // Name so taps can be recognized
            flower.name = "flower-\(UUID().uuidString)"
            flower.generateCollisionShapes(recursive: true)

            anchor.addChild(flower)
            arView.scene.addAnchor(anchor)
            gardenAnchors.append(anchor)
        }

        // Wire SwiftUI buttons
        func bindUI() {
            NotificationCenter.default.addObserver(forName: .toggleMesh, object: nil, queue: .main) { [weak self] note in
                guard let self, let arView = self.arView,
                      let on = note.object as? Bool else { return }
                if on { arView.debugOptions.insert(.showSceneUnderstanding) }
                else { arView.debugOptions.remove(.showSceneUnderstanding) }
            }
            NotificationCenter.default.addObserver(forName: .clearGarden, object: nil, queue: .main) { [weak self] _ in
                guard let self, let arView = self.arView else { return }
                self.gardenAnchors.forEach { arView.scene.removeAnchor($0) }
                self.gardenAnchors.removeAll()
            }
            NotificationCenter.default.addObserver(forName: .scatterNow, object: nil, queue: .main) { [weak self] note in
                guard let self, let n = note.object as? Int else { return }
                self.scatterFlowers(count: n)
            }
        }

        // Scatter only once automatically when tracking is stable
        func startAutoScatterOnce(targetCount: Int) {
            guard !hasAutoScattered else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.waitForStableTrackingThenScatter(targetCount)
            }
        }

        private func waitForStableTrackingThenScatter(_ count: Int) {
            guard let arView else { return }
            if case .normal = arView.session.currentFrame?.camera.trackingState ?? .notAvailable {
                scatterFlowers(count: count)
                hasAutoScattered = true

                // start watching for "no flowers in view"
                startFlowerMonitor()
            } else {
                // re-check shortly, but won’t repeat after success
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                    self?.waitForStableTrackingThenScatter(count)
                }
            }
        }

        // Scatter N flowers: sample a sparse grid of screen points and raycast to existing geometry
        func scatterFlowers(count: Int) {
            guard let arView else { return }
            let cols = max(2, Int(ceil(sqrt(Double(count)))))
            let rows = max(2, Int(ceil(Double(count) / Double(cols))))
            var placed = 0

            for r in 0..<rows {
                for c in 0..<cols {
                    if placed >= count { break }
                    let u = (CGFloat(c) + .random(in: 0.25...0.75)) / CGFloat(cols)
                    let v = (CGFloat(r) + .random(in: 0.25...0.75)) / CGFloat(rows)
                    let pt = CGPoint(x: arView.bounds.width * u, y: arView.bounds.height * v)

                    if let hit = arView.raycast(from: pt, allowing: .existingPlaneGeometry, alignment: .any).first {
                        plantFlower(at: hit.worldTransform)
                        placed += 1
                    }
                }
            }
        }

        // Tap → find a flower (walk up to a named ancestor) → notify SwiftUI
        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let arView else { return }
            let pt = g.location(in: arView)
            guard let hit = arView.entity(at: pt) else { return }

            // Walk up the parent chain until we find "flower-" on the name
            var node: Entity? = hit
            var found = false
            while let e = node {
                if let me = e as? ModelEntity, me.name.hasPrefix("flower-") {
                    found = true
                    break
                }
                node = e.parent
            }
            if found {
                NotificationCenter.default.post(name: .flowerTapped, object: nil)
            }
        }

        // MARK: - NEW: monitoring logic

        // start timer to check every second
        func startFlowerMonitor() {
            visibilityTimer?.invalidate()
            visibilityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.checkFlowerVisibility()
            }
            lastFlowerVisibleTime = .now
        }

        // every frame, see if any flower is in front of camera
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard let arView else { return }

            let camTransform = frame.camera.transform
            let camPos = simd_make_float3(camTransform.columns.3)
            let forward = -simd_make_float3(camTransform.columns.2) // camera forward

            var visibleCount = 0
            for anchor in gardenAnchors {
                guard let flower = anchor.children.first else { continue }
                let pos = flower.position(relativeTo: nil)
                let dir = normalize(pos - camPos)
                let dot = simd_dot(dir, forward)
                if dot > 0.5 && distance(pos, camPos) < 2.5 {
                    visibleCount += 1
                }
            }

            if visibleCount > 0 {
                lastFlowerVisibleTime = .now
            }
        }

        // called by timer
        private func checkFlowerVisibility() {
            guard let arView else { return }

            let timeSinceSeen = Date().timeIntervalSince(lastFlowerVisibleTime)
            
            if timeSinceSeen > 1 {
                for i in 0..<2 {
                    // Wider scatter in screen space
                    let center = CGPoint(
                        x: arView.bounds.midX + CGFloat.random(in: -120...120),
                        y: arView.bounds.midY + CGFloat.random(in: -120...120)
                    )
                    if let hit = arView.raycast(from: center,
                                                allowing: .existingPlaneGeometry,
                                                alignment: .any).first {

                        var transform = hit.worldTransform

                        // Apply a small world offset (in meters) for extra spacing
                        let randomOffset = SIMD3<Float>(
                            Float.random(in: -0.25...0.25),
                            0,
                            Float.random(in: -0.25...0.25)
                        )
                        transform.columns.3.x += randomOffset.x
                        transform.columns.3.z += randomOffset.z

                        plantFlower(at: transform)
                    }
                }
                lastFlowerVisibleTime = .now
            }
        }

        // Compatibility-safe procedural flower (box stem + squashed spheres)
        private func makeProceduralFlower() -> ModelEntity {
            let stemBox = MeshResource.generateBox(size: 0.01)
            let stemMat  = SimpleMaterial(color: UIColor(red: 0.05, green: 0.6, blue: 0.2, alpha: 1), isMetallic: false)
            let stem = ModelEntity(mesh: stemBox, materials: [stemMat])
            stem.scale = [1, 18, 1]
            stem.position.y = 0.09

            let petalMesh = MeshResource.generateSphere(radius: 0.018)
            let petalMat  = SimpleMaterial(color: UIColor(red: 0.95, green: 0.35, blue: 0.55, alpha: 1), isMetallic: false)
            var petals: [ModelEntity] = []
            for i in 0..<8 {
                let angle = Float(i) * (.pi * 2 / 8)
                let p = ModelEntity(mesh: petalMesh, materials: [petalMat])
                p.scale = [1.8, 0.6, 1.0]
                p.position = [0, 0.175, 0]
                p.orientation = simd_quatf(angle: angle, axis: [0,1,0]) * simd_quatf(angle: .pi/2.8, axis: [1,0,0])
                petals.append(p)
            }

            let center = ModelEntity(mesh: .generateSphere(radius: 0.015),
                                     materials: [SimpleMaterial(color: .yellow, isMetallic: false)])
            center.position.y = 0.175

            let leafMesh = MeshResource.generateSphere(radius: 0.02)
            let leafMat  = SimpleMaterial(color: UIColor(red: 0.1, green: 0.7, blue: 0.25, alpha: 1), isMetallic: false)
            let leafL = ModelEntity(mesh: leafMesh, materials: [leafMat])
            leafL.scale = [2.2, 0.5, 1.2]; leafL.position = [-0.03, 0.08, 0]; leafL.orientation = simd_quatf(angle: .pi/3, axis: [0,0,1])
            let leafR = ModelEntity(mesh: leafMesh, materials: [leafMat])
            leafR.scale = [2.2, 0.5, 1.2]; leafR.position = [ 0.03, 0.11, 0]; leafR.orientation = simd_quatf(angle: -.pi/3, axis: [0,0,1])

            let root = ModelEntity()
            [stem, center, leafL, leafR].forEach { root.addChild($0) }
            petals.forEach { root.addChild($0) }
            return root
        }
    }
}

// MARK: - Small helpers
extension float4x4 {
    init(translation t: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4<Float>(t.x, t.y, t.z, 1)
    }
}
extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float { min(max(self, range.lowerBound), range.upperBound) }
}
