import SwiftUI
import RealityKit
import ARKit
import Combine
import PhotosUI
import AVKit

struct LoginView: View {
    @State private var username = ""
    @State private var password = ""
    @State private var loggedIn = false
    @State private var showLoginError = false
    @State private var errorMessage = ""
    @State private var showARView = false

    var body: some View {
        if loggedIn {
            if showARView {
                ZStack(alignment: .bottom) {
                    ContentView()
                    Button("Go to Uploads") {
                        showARView.toggle()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 30)
                    .background(Color.clear)
                }
            } else {
                VStack {
                    HStack {
                        Button("Go to AR Experience") {
                            showARView.toggle()
                        }
                        .buttonStyle(.borderedProminent)
                        .padding()
                    }
                    MediaUploadView()
                }
            }
        } else {
            VStack(spacing: 16) {
                Text("Login to Continue")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.bottom, 8)

                TextField("Username", text: $username)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)

                SecureField("Password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button("Login") {
                    APIService.shared.login(username: username, password: password) { success, _ in
                        DispatchQueue.main.async {
                            if success {
                                loggedIn = true
                            } else {
                                errorMessage = "Invalid username or password"
                                showLoginError = true
                            }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
            .padding()
            .alert(isPresented: $showLoginError) {
                Alert(
                    title: Text("Login Failed"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
}

struct MediaUploadView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedMediaData: Data?
    @State private var selectedMediaType: String = "" // "image" or "video"
    @State private var uploadStatus: String = ""
    @State private var isUploading = false
    @State private var caption: String = ""
    @State private var showQueryBox = false
    @State private var customQuery = ""
    @State private var queryResponse = ""
    
    // Computed property for cached images
    var cachedImages: [UIImage] {
        let cacheFolder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("FlowerImageCache")
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheFolder, includingPropertiesForKeys: nil) else { return [] }
        return files.compactMap { UIImage(contentsOfFile: $0.path) }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Upload a Photo or Video")
                .font(.title2)
                .bold()

            // MARK: Media Picker
            PhotosPicker(selection: $selectedItem, matching: .any(of: [.images, .videos])) {
                Label("Choose File", systemImage: "photo.on.rectangle")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(10)
            }
            .onChange(of: selectedItem) { newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        selectedMediaData = data
                        selectedMediaType = newItem.supportedContentTypes.contains(.movie) ? "video" : "image"
                        uploadStatus = "✅ Selected \(selectedMediaType)"
                    }
                }
            }

            // MARK: Preview
            if let data = selectedMediaData {
                if selectedMediaType == "image", let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 200)
                        .cornerRadius(12)
                } else if selectedMediaType == "video" {
                    Text("🎬 Video selected (preview not shown)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }

            // Caption TextField
            TextField("Enter caption", text: $caption)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            // Show cached images previews
            if !cachedImages.isEmpty {
                Text("Previously Cached Images")
                    .font(.headline)
                    .padding(.top)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(cachedImages.enumerated()), id: \.offset) { _, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipped()
                                .cornerRadius(8)
                                .shadow(radius: 4)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            Divider()
            Text("Custom Query to Backend")
                .font(.headline)

            Button("Open Query Box") {
                showQueryBox = true
            }
            .buttonStyle(.bordered)

            if showQueryBox {
                VStack(spacing: 10) {
                    TextField("Enter your custom query", text: $customQuery)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.horizontal)

                    Button("Send Query") {
                        guard !customQuery.isEmpty else {
                            queryResponse = "⚠️ Please enter a query first."
                            return
                        }
                        APIService.shared.sendCustomQuery(customQuery) { response in
                            DispatchQueue.main.async {
                                queryResponse = response
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if !queryResponse.isEmpty {
                Text(queryResponse)
                    .foregroundColor(.gray)
                    .font(.subheadline)
                    .padding(.top, 4)
            }
            Divider()

            // MARK: Upload Button
            Button(action: {
                guard let mediaData = selectedMediaData else {
                    uploadStatus = "⚠️ No media selected"
                    return
                }
                isUploading = true
                APIService.shared.uploadMedia(data: mediaData, type: selectedMediaType, caption: caption) { success in
                    DispatchQueue.main.async {
                        isUploading = false
                        uploadStatus = success ? "✅ Upload successful!" : "❌ Upload failed"
                        // Cache the uploaded image if it's an image type
                        if success, selectedMediaType == "image", let data = selectedMediaData, let image = UIImage(data: data) {
                            let id = UUID().uuidString
                            ImageCache.shared.saveImage(image, for: id)
                        }
                        caption = ""
                        selectedMediaData = nil
                    }
                }
            }) {
                Text("Upload to Server")
            }
            .disabled(isUploading)
            .buttonStyle(.borderedProminent)
            
            if isUploading {
                ProgressView("Uploading...")
            }
            
            Text(uploadStatus)
                .foregroundColor(.gray)
                .font(.subheadline)
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - Notifications from SwiftUI → AR coordinator
extension Notification.Name {
    static let toggleMesh   = Notification.Name("toggleMesh")
    static let clearGarden  = Notification.Name("clearGarden")
    static let scatterNow   = Notification.Name("scatterNow")   // payload: Int (how many)
    static let flowerTapped = Notification.Name("flowerTapped") // AR → SwiftUI
}

// MARK: - Main SwiftUI View
struct ContentView: View {
    @State private var meshOn = false
    @State private var showPopup = false
    @State private var showConnectionAlert = false
    @State private var connectionMessage = ""
    @State private var currentMemory: MediaItem?
    
    var body: some View {
        ZStack {
            ARViewContainer().ignoresSafeArea()
            
            // Popup showing memory content
            if showPopup, let memory = currentMemory {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation { showPopup = false } }

                VStack {
                    if let cached = ImageCache.shared.image(for: memory.id) {
                        Image(uiImage: cached)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 300)
                            .cornerRadius(16)
                            .shadow(radius: 10)
                            .padding()
                    } else {
                        AsyncImage(url: URL(string: memory.url)) { image in
                            image.resizable()
                                 .scaledToFit()
                                 .frame(maxWidth: 300)
                                 .cornerRadius(16)
                                 .shadow(radius: 10)
                                 .padding()
                        } placeholder: {
                            ProgressView()
                        }
                    }

                    Text(memory.caption)
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()

                    Button("Close") {
                        withAnimation { showPopup = false }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .transition(.scale.combined(with: .opacity))
            }

            // Controls overlay
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

                    Button("Test Backend Connection") {
                        connectionMessage = "Checking..."
                        showConnectionAlert = true
                        
                        print("🌐 Attempting to contact backend at \(APIService.shared.baseURL)/random_memories")
                        
                        APIService.shared.fetchRandomMemories { items in
                            DispatchQueue.main.async {
                                if items.isEmpty {
                                    connectionMessage = "⚠️ Backend not reachable or no media uploaded."
                                } else {
                                    connectionMessage = "✅ Connected! Received \(items.count) memories."
                                }
                                showConnectionAlert = true
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .alert(isPresented: $showConnectionAlert) {
                        Alert(
                            title: Text("Backend Connection"),
                            message: Text(connectionMessage),
                            dismissButton: .default(Text("OK"))
                        )
                    }
                }

                Spacer()
            }
            .padding(.top, 16)
            .padding(.horizontal, 12)
        }
        // Popup opens when flower tapped
        .onReceive(NotificationCenter.default.publisher(for: .flowerTapped)) { note in
            if let memory = note.object as? MediaItem {
                currentMemory = memory
                withAnimation(.spring()) { showPopup = true }
            }
        }.onAppear {
            preloadImages(count: 5)
        }
    }
    private func preloadImages(count: Int) {
        APIService.shared.fetchRandomMemories { items in
            let topItems = Array(items.prefix(count))
            for memory in topItems {
                guard let url = URL(string: memory.url) else { continue }
                // Skip if already cached
                if ImageCache.shared.isCached(memory.id) { continue }

                URLSession.shared.dataTask(with: url) { data, _, _ in
                    if let data = data, let image = UIImage(data: data) {
                        ImageCache.shared.saveImage(image, for: memory.id)
                        print("✅ Cached image for:", memory.caption)
                    }
                }.resume()
            }
        }
    }
}

// MARK: - AR Container
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

        // Coaching overlay
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

        // Coordinator setup
        context.coordinator.arView = arView
        arView.session.delegate = context.coordinator
        context.coordinator.bindUI()

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tap)

        // Scatter flowers once
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
        private var lastFlowerVisibleTime: Date = .now
        private var visibilityTimer: Timer?

        // MARK: - Load Flower
        private func loadFlowerModel() -> ModelEntity {
            if let cached = flowerCachedOriginal {
                return cached.clone(recursive: true)
            }
            if let model = try? Entity.loadModel(named: flowerUSDZName) as? ModelEntity {
                flowerCachedOriginal = model
                return model.clone(recursive: true)
            } else {
                return makeProceduralFlower()
            }
        }

        // Normalize height and shadow
        private func normalizeAndGround(_ entity: ModelEntity, targetHeight: Float = 0.15) {
            let bounds = entity.visualBounds(relativeTo: nil)
            let currentHeight = max(0.001, bounds.extents.y)
            let scaleFactor = targetHeight / currentHeight
            entity.scale *= scaleFactor

            let newBounds = entity.visualBounds(relativeTo: nil)
            let lift = -newBounds.min.y
            entity.position.y += lift

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

        // MARK: - Place Flowers
        private func plantFlower(at transform: float4x4) {
            guard let arView else { return }
            let anchor = AnchorEntity(world: transform)
            let flower = loadFlowerModel()
            // ✅ Limit to 10 flowers at a time
            if gardenAnchors.count >= 10 {
                // Remove the oldest flower
                if let oldest = gardenAnchors.first {
                    arView.scene.removeAnchor(oldest)
                    gardenAnchors.removeFirst()
                }
            }
            // Random height + scale
            let randomHeight: Float = Float.random(in: 0.13...0.18)
            normalizeAndGround(flower, targetHeight: randomHeight)
            let widthScale: Float = Float.random(in: 0.9...1.1)
            flower.scale.x *= widthScale
            flower.scale.z *= widthScale
            flower.orientation *= simd_quatf(angle: Float.random(in: -0.25...0.25), axis: [0,1,0])
            flower.scale *= Float.random(in: 0.9...1.15)

            // Physics and collisions
            let physMat = PhysicsMaterialResource.generate(friction: 0.9, restitution: 0.05)
            let body = PhysicsBodyComponent(massProperties: .default, material: physMat, mode: .static)
            flower.components.set(body)
            flower.generateCollisionShapes(recursive: true)
            flower.name = "flower-\(UUID().uuidString)"

            // Assign one random memory
            APIService.shared.fetchRandomMemories { items in
                if let randomMemory = items.randomElement() {
                    flower.components.set(MemoryComponent(memory: randomMemory))
                }
            }

            anchor.addChild(flower)
            arView.scene.addAnchor(anchor)
            gardenAnchors.append(anchor)
        }

        // MARK: - Scatter / Auto
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
                startFlowerMonitor()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                    self?.waitForStableTrackingThenScatter(count)
                }
            }
        }

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

        // MARK: - Tap Handling
        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let arView else { return }
            let pt = g.location(in: arView)
            guard let hit = arView.entity(at: pt) else { return }

            var node: Entity? = hit
            while let e = node {
                if let me = e as? ModelEntity, me.name.hasPrefix("flower-") {
                    if let memoryComp = me.components[MemoryComponent.self] as? MemoryComponent {
                        NotificationCenter.default.post(name: .flowerTapped, object: memoryComp.memory)
                    } else {
                        print("⚠️ Flower has no memory component")
                    }
                    return
                }
                node = e.parent
            }
        }

        // MARK: - Helpers
        private func startFlowerMonitor() {
            visibilityTimer?.invalidate()
            visibilityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.checkFlowerVisibility()
            }
            lastFlowerVisibleTime = .now
        }
        
        // MARK: - Visibility check
        private func checkFlowerVisibility() {
            guard let arView else { return }

            // Get the camera transform
            guard let frame = arView.session.currentFrame else { return }
            let cameraTransform = frame.camera.transform
            let cameraPosition = simd_make_float3(cameraTransform.columns.3)
            let cameraForward = -simd_make_float3(cameraTransform.columns.2)

            // Count how many flowers are in view
            var visibleCount = 0
            for anchor in gardenAnchors {
                guard let flower = anchor.children.first else { continue }
                let flowerPosition = flower.position(relativeTo: nil)

                // Vector from camera to flower
                let directionToFlower = normalize(flowerPosition - cameraPosition)
                let distance = simd_distance(cameraPosition, flowerPosition)

                // Dot product to check if within ~45° of the camera's forward direction
                let dot = simd_dot(cameraForward, directionToFlower)
                let isFacing = dot > 0.7   // adjust for FOV
                let isCloseEnough = distance < 3.0

                if isFacing && isCloseEnough {
                    visibleCount += 1
                }
            }

            // If we see at least 1 flower, reset the timer
            if visibleCount > 0 {
                lastFlowerVisibleTime = .now
                return
            }

            // Otherwise, if it's been >5 seconds since any were seen, spawn 2 new ones
            let timeSinceSeen = Date().timeIntervalSince(lastFlowerVisibleTime)
            if timeSinceSeen > 5 {
                print("🌸 No flowers in view for 5s — planting new ones")
                for _ in 0..<2 {
                    let randomPoint = CGPoint(
                        x: arView.bounds.midX + CGFloat.random(in: -100...100),
                        y: arView.bounds.midY + CGFloat.random(in: -100...100)
                    )

                    if let hit = arView.raycast(from: randomPoint,
                                                allowing: .existingPlaneGeometry,
                                                alignment: .any).first {
                        var transform = hit.worldTransform
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
                p.orientation = simd_quatf(angle: angle, axis: [0,1,0]) *
                                simd_quatf(angle: .pi/2.8, axis: [1,0,0])
                petals.append(p)
            }

            let center = ModelEntity(mesh: .generateSphere(radius: 0.015),
                                     materials: [SimpleMaterial(color: .yellow, isMetallic: false)])
            center.position.y = 0.175

            let leafMesh = MeshResource.generateSphere(radius: 0.02)
            let leafMat  = SimpleMaterial(color: UIColor(red: 0.1, green: 0.7, blue: 0.25, alpha: 1), isMetallic: false)
            let leafL = ModelEntity(mesh: leafMesh, materials: [leafMat])
            leafL.scale = [2.2, 0.5, 1.2]; leafL.position = [-0.03, 0.08, 0]
            leafL.orientation = simd_quatf(angle: .pi/3, axis: [0,0,1])
            let leafR = ModelEntity(mesh: leafMesh, materials: [leafMat])
            leafR.scale = [2.2, 0.5, 1.2]; leafR.position = [0.03, 0.11, 0]
            leafR.orientation = simd_quatf(angle: -.pi/3, axis: [0,0,1])

            let root = ModelEntity()
            [stem, center, leafL, leafR].forEach { root.addChild($0) }
            petals.forEach { root.addChild($0) }
            return root
        }
    }
}

// MARK: - Custom Component
struct MemoryComponent: Component {
    var memory: MediaItem
}
extension MemoryComponent: Codable {}

// MARK: - Helpers
extension float4x4 {
    init(translation t: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4<Float>(t.x, t.y, t.z, 1)
    }
}
extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
