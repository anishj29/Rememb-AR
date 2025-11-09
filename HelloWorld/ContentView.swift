import SwiftUI
import RealityKit
import ARKit
import Combine
import PhotosUI
import AVKit
// MARK: - Survey View
struct SurveyView: View {
    @State private var survey: Survey?
    @State private var responses: [Int: String] = [:]
    @State private var statusMessage = ""
    @State private var isSubmitted = false
    @State private var incorrectQuestions: Set<UUID> = []
    @State private var correctQuestions: Set<UUID> = []

    var body: some View {
        ZStack {
            Color(red: 0.19, green: 0.29, blue: 0.21).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    if let currentSurvey = survey {
                        Text("Memory Recall Survey")
                            .font(.title2)
                            .bold()
                            .foregroundColor(.white)
                            .padding(.bottom, 8)
                        ForEach(currentSurvey.survey) { question in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(question.question)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if question.type == "text" {
                                    TextField("Enter your answer", text: Binding(
                                        get: { responses[question.id.hashValue] ?? "" },
                                        set: { responses[question.id.hashValue] = $0 }
                                    ))
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .disabled(isSubmitted)
                                } else if question.type == "multiple_choice", let options = question.options {
                                    ForEach(options, id: \.self) { option in
                                        Button(option) {
                                            if !isSubmitted {
                                                responses[question.id.hashValue] = option
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(
                                            incorrectQuestions.contains(question.id)
                                                ? .red
                                                : (correctQuestions.contains(question.id)
                                                   ? .green
                                                   : (responses[question.id.hashValue] == option ? .blue : .gray))
                                        )
                                        .disabled(isSubmitted)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                        }
                        Button("Submit Survey") {
                            guard let currentSurvey = survey else { return }
                            incorrectQuestions.removeAll()
                            correctQuestions.removeAll()
                            for question in currentSurvey.survey {
                                if let userAnswer = responses[question.id.hashValue] {
                                    if userAnswer == question.correct_answer {
                                        correctQuestions.insert(question.id)
                                    } else {
                                        incorrectQuestions.insert(question.id)
                                    }
                                } else {
                                    incorrectQuestions.insert(question.id)
                                }
                            }
                            isSubmitted = true
                            let correctAnswers: [Int: String] = [:]
                            APIService.shared.sendSurveyResults(currentSurvey, responses: responses, correctAnswers: correctAnswers) { result in
                                DispatchQueue.main.async {
                                    statusMessage = result
                                }
                            }
                        }
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(red: 0.8, green: 0.4, blue: 0.4))
                        .cornerRadius(10)
                        .padding(.top, 16)
                        .disabled(isSubmitted)
                        .tint(isSubmitted ? .gray : Color(red: 0.8, green: 0.4, blue: 0.4))
                    } else {
                        ProgressView("Loading survey...")
                            .onAppear {
                                APIService.shared.fetchSurvey { survey in
                                    DispatchQueue.main.async {
                                        self.survey = survey
                                    }
                                }
                            }
                    }
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .foregroundColor(.white)
                            .padding(.top, 10)
                    }
                    Spacer()
                }
                .padding()
            }
        }
    }
}


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
                }
            } else {
                ZStack{
                    Color(red: 0.19, green: 0.29, blue: 0.21)
                        .ignoresSafeArea()
                    VStack {
                        HStack {
                            Button("Go to AR Experience") {
                                showARView.toggle()
                            }
                            .padding()
                            .background(Color(red: 0.25, green: 0.7, blue: 0.3))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        MediaUploadView()
                    }
                }
            }
        } else {
            ZStack {
                Color(red: 0.19, green: 0.29, blue: 0.21)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("Login to Continue")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.bottom, 8)
                        .foregroundColor(.white)

                    TextField("Username", text: $username)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .colorScheme(.dark)

                    SecureField("Password", text: $password)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .colorScheme(.dark)

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
                    .tint(.green)
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
    @State private var selectedTab = 0
    @State private var cacheRefreshTrigger = false

    // Computed property for cached images
    var cachedImages: [UIImage] {
        let cacheFolder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("FlowerImageCache")
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheFolder, includingPropertiesForKeys: nil) else { return [] }
        return files.compactMap { UIImage(contentsOfFile: $0.path) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 0.19, green: 0.29, blue: 0.21)
                .ignoresSafeArea()
            TabView(selection: $selectedTab) {
                // Home Tab
                ZStack {
                    Color(red: 0.19, green: 0.29, blue: 0.21).ignoresSafeArea()
                    VStack(spacing: 32) {
                        Image("Subject")
                            .resizable()
                            .frame(width: 80, height: 80)
                            .cornerRadius(12)
                        Text("Welcome to the Memory Garden")
                            .font(.title)
                            .bold()
                            .foregroundColor(.white)
                        Text("Capture, upload, and recall your favorite moments in AR.\nNavigate using the tabs below.")
                            .font(.body)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Spacer()
                    }
                    .padding(.top, 60)
                    .padding(.horizontal)
                }
                .tag(0)
                .tabItem {
                    Label("Home", systemImage: "house")
                }

                // Upload Tab
                ZStack {
                    Color(red: 0.19, green: 0.29, blue: 0.21).ignoresSafeArea()
                    ScrollView {
                        VStack(spacing: 20) {
                            // Go to AR Experience button at top
                            Text("Upload a Photo")
                                .font(.title2)
                                .bold()

                            // MARK: Media Picker
                            PhotosPicker(selection: $selectedItem, matching: .any(of: [.images, .videos])) {
                                Label("Choose File", systemImage: "photo.on.rectangle")
                                    .font(.headline)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color(red: 0.35, green: 0.56, blue: 0.35))
                                    .foregroundColor(.white)
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
                                            cacheRefreshTrigger.toggle()
                                        }
                                        caption = ""
                                        selectedMediaData = nil
                                    }
                                }
                            }) {
                                Text("Upload to Server")
                                    .foregroundColor(.white)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color(red: 0.8, green: 0.4, blue: 0.4))
                                    .cornerRadius(8)
                            }
                            .disabled(isUploading)

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
                .tag(1)
                .tabItem {
                    Label("Upload", systemImage: "square.and.arrow.up")
                }

                // Query Tab
                ZStack {
                    Color(red: 0.19, green: 0.29, blue: 0.21).ignoresSafeArea()
                    ScrollView {
                        VStack(spacing: 20) {
                            Text("Custom Query to Backend")
                                .font(.title2)
                                .bold()

                            Button(action: {
                                showQueryBox = true
                            }) {
                                Text("Open Query Box")
                                    .foregroundColor(.white)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color(red: 0.85, green: 0.55, blue: 0.45))
                                    .cornerRadius(10)
                            }

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

                            Spacer()
                        }
                        .padding()
                    }
                }
                .tag(2)
                .tabItem {
                    Label("Query", systemImage: "magnifyingglass")
                }

                // Cache Tab
                ZStack {
                    Color(red: 0.19, green: 0.29, blue: 0.21).ignoresSafeArea()
                    ScrollView {
                        VStack(spacing: 20) {
                            Group {
                                let images = cachedImages
                                if !images.isEmpty {
                                    Text("Previously Cached Images")
                                        .font(.title2)
                                        .bold()
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 10) {
                                            ForEach(Array(images.enumerated()), id: \.offset) { _, image in
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
                                    Button(action: {
                                        let cacheFolder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("FlowerImageCache")
                                        if let files = try? FileManager.default.contentsOfDirectory(at: cacheFolder, includingPropertiesForKeys: nil) {
                                            for file in files {
                                                try? FileManager.default.removeItem(at: file)
                                            }
                                        }
                                        cacheRefreshTrigger.toggle()
                                    }) {
                                        Text("Clear Cached Images")
                                            .font(.headline).bold()
                                            .foregroundColor(Color.red)
                                            .padding()
                                            .frame(maxWidth: .infinity)
                                            .background(Color(red: 0.25, green: 0.4, blue: 0.25))
                                            .cornerRadius(10)
                                    }
                                    .padding(.top, 8)
                                } else {
                                    Text("No cached images found.")
                                        .foregroundColor(.gray)
                                        .padding(.top, 40)
                                }
                            }
                            Spacer()
                        }
                        .padding()
                        .id(cacheRefreshTrigger)
                    }
                }
                .tag(3)
                .tabItem {
                    Label("Cache", systemImage: "photo.stack")
                }

                // Survey Tab
                ZStack {
                    Color(red: 0.19, green: 0.29, blue: 0.21).ignoresSafeArea()
                    SurveyView()
                }
                .tag(4)
                .tabItem {
                    Label("Survey", systemImage: "doc.text")
                }
            }
            .accentColor(Color(red: 0.35, green: 0.56, blue: 0.35))
        }
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
        // Popup opens when flower tapped
        .onReceive(NotificationCenter.default.publisher(for: .flowerTapped)) { note in
            if let memory = note.object as? MediaItem {
                currentMemory = memory
                withAnimation(.spring()) { showPopup = true }
            }
        }
        .onAppear {
            // Preload random images using cache method
            ImageCache.shared.preloadRandomImages(batchSize: 5)
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
        // Track which memory IDs have been used for this batch of flowers
        static var usedMemoryIDs = Set<String>()
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

            // Assign one random memory, avoiding duplicates in this batch
            APIService.shared.fetchRandomMemories { items in
                // Filter out IDs already used in this batch
                let unused = items.filter { !Coordinator.usedMemoryIDs.contains($0.id) }
                let selectedMemory: MediaItem?
                if let memory = unused.randomElement() {
                    selectedMemory = memory
                } else {
                    // If all used, just pick any (should be rare)
                    selectedMemory = items.randomElement()
                }
                if let memory = selectedMemory {
                    flower.components.set(MemoryComponent(memory: memory))
                    Coordinator.usedMemoryIDs.insert(memory.id)
                }
                // After 10 flowers, reset usedMemoryIDs for a new batch
                DispatchQueue.main.async {
                    if self.gardenAnchors.count >= 10 {
                        Coordinator.usedMemoryIDs.removeAll()
                    }
                }
            }

            // Lazy cache refresh: if cache is low, trigger background refresh
            if ImageCache.shared.cachedCount() <= 2 {
                DispatchQueue.global(qos: .background).async {
                    ImageCache.shared.ensureMinimumCache()
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

            // Otherwise, if it's been >3 seconds since any were seen, spawn 3 new ones
            let timeSinceSeen = Date().timeIntervalSince(lastFlowerVisibleTime)
            if timeSinceSeen > 3 {
                print("🌸 No flowers in view for 3s — planting new ones")
                for _ in 0..<3 {
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
