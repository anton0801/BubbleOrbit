
import SwiftUI
import Combine
import WebKit
import AppsFlyerLib
import Firebase
import FirebaseMessaging

extension Color {
    static let cosmicBlack = Color(hex: "#0D0D1A")
    static let cosmicPurple = Color(hex: "#1A0D2E")
    static let cosmicBlue = Color(hex: "#2B0D4F")
    
    static let taskPink = Color(hex: "#FF4FBF")
    static let glowPurple = Color(hex: "#B84FFF")
    static let highlightBlue = Color(hex: "#4FFFE0")
    static let orbitPurple = Color(hex: "#7A4FFF").opacity(0.3)
    
    static let textWhite = Color(hex: "#FFFFFF")
    static let textGray = Color(hex: "#CCCCCC")
    static let accentGold = Color(hex: "#FFD84F")
    static let darkGray = Color(hex: "#333333")
}

// Helper for hex colors
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// Sample Task model with subtasks, deadline, and completedAt for persistence and auto-delete
struct Task: Identifiable, Codable, Equatable {
    var id: UUID // Changed to var for decoding
    var title: String
    var description: String
    var priority: Int // 1 = important (close to center), higher = lower priority
    var isCompleted: Bool = false
    var completedAt: Date? // Timestamp for completion to auto-delete after 60 min
    var subtasks: [Task] = []
    var deadline: Date? = nil
    
    enum CodingKeys: String, CodingKey {
        case id, title, description, priority, isCompleted, completedAt, subtasks, deadline
    }
    
    init(title: String, description: String, priority: Int, deadline: Date? = nil) {
        self.id = UUID()
        self.title = title
        self.description = description
        self.priority = priority
        self.deadline = deadline
    }
    
    static func == (lhs: Task, rhs: Task) -> Bool {
        lhs.id == rhs.id
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(priority, forKey: .priority)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encode(completedAt, forKey: .completedAt)
        try container.encode(subtasks, forKey: .subtasks)
        try container.encode(deadline, forKey: .deadline)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.description = try container.decode(String.self, forKey: .description)
        self.priority = try container.decode(Int.self, forKey: .priority)
        self.isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        self.completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        self.subtasks = try container.decode([Task].self, forKey: .subtasks)
        self.deadline = try container.decodeIfPresent(Date.self, forKey: .deadline)
    }
}

// HomeView with persistence and auto-delete
struct HomeView: View {
    @State private var tasks: [Task] = []
    @AppStorage("tasksData") private var tasksData: Data = Data()
    
    @State private var selectedTask: Task? = nil
    @State private var editingTask: Task? = nil
    @State private var showAddTask = false
    @State private var showEditTask = false
    @State private var showTaskDetail = false
    @State private var showAddSubtask = false
    @State private var showProfile = false
    @State private var angleOffset: Double = 0 // For orbiting animation
    
    @AppStorage("animationsEnabled") private var animationsEnabled: Bool = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @AppStorage("completedCount") private var completedCount: Int = 0
    @AppStorage("deletedCount") private var deletedCount: Int = 0
    
    let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect() // Smooth animation timer
    let cleanupTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect() // Check for auto-delete every 10s
    
    var activeTasks: [Task] {
        tasks.filter { !$0.isCompleted && !isOverdue(task: $0) }
    }
    
    var completedTasks: [Task] {
        tasks.filter { $0.isCompleted }
    }
    
    var overdueTasks: [Task] {
        tasks.filter { !$0.isCompleted && isOverdue(task: $0) }
    }
    
    func isOverdue(task: Task) -> Bool {
        if let deadline = task.deadline, deadline < Date() {
            return true
        }
        return false
    }
    
    var body: some View {
        ZStack {
            // Cosmic gradient background with subtle stars for beauty
            LinearGradient(gradient: Gradient(colors: [.cosmicBlack, .cosmicPurple, .cosmicBlue]), startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            
            // Subtle star field for more cosmic feel
            StarFieldView()
                .ignoresSafeArea()
            
            // Background completed and overdue tasks
            BackgroundTasksView(completed: completedTasks, overdue: overdueTasks) { task in
                selectedTask = task
                showTaskDetail = true
            }
            
            // Orbit View
            GeometryReader { geometry in
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                
                // Profile central pink ball
                Circle()
                    .fill(Color.taskPink)
                    .frame(width: 50, height: 50)
                    .shadow(color: .glowPurple, radius: 10)
                    .position(center)
                    .scaleEffect(animationsEnabled ? 1 + 0.1 * sin(angleOffset / 10) : 1)
                    .onTapGesture {
                        showProfile = true
                    }
                
                // Orbits (concentric circles with faint glow)
                ForEach(1..<4) { ring in
                    Circle()
                        .stroke(Color.orbitPurple, lineWidth: 1)
                        .frame(width: CGFloat(ring) * 150, height: CGFloat(ring) * 150)
                        .blur(radius: 2) // Soft glow on orbits
                        .position(center)
                }
                
                // Active tasks as planets with orbiting animation
                ForEach(activeTasks) { task in
                    let baseAngle = Double(task.id.hashValue % 360)
                    let animatedAngle = baseAngle + angleOffset / Double(task.priority) // Slower for outer orbits
                    let radius = Double(task.priority) * 75
                    let x = center.x + radius * cos(animatedAngle * .pi / 180)
                    let y = center.y + radius * sin(animatedAngle * .pi / 180)
                    
                    PlanetView(task: task, isSelected: selectedTask?.id == task.id)
                        .position(x: x, y: y)
                        .onTapGesture {
                            selectedTask = task
                            showTaskDetail = true
                        }
                }
            }
            .onReceive(timer) { _ in
                if animationsEnabled {
                    withAnimation(.linear(duration: 0.05)) {
                        angleOffset += 1 // Increment angle for smooth rotation
                        // Removed the reset to 0 for continuous orbiting without potential jumps
                    }
                }
            }
            
            // Add Task button with hover effect
            VStack {
                Spacer()
                Button(action: {
                    showAddTask = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .resizable()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.taskPink)
                        .shadow(color: .glowPurple, radius: 10) // Increased shadow
                        .scaleEffect(animationsEnabled ? 1 + 0.05 * sin(angleOffset / 5) : 1) // Subtle pulse
                }
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            loadTasks()
        }
        .onChange(of: tasks) { _ in
            saveTasks()
        }
        .onReceive(cleanupTimer) { _ in
            cleanupCompletedTasks()
        }
        .sheet(isPresented: $showAddTask) {
            AddTaskView(onAdd: { newTask in
                tasks.append(newTask)
                showAddTask = false
            })
        }
        .sheet(isPresented: $showEditTask) {
            EditTaskView(
                task: editingTask ?? Task(title: "", description: "", priority: 1),
                onSave: { updatedTask in
                    if let index = tasks.firstIndex(where: { $0.id == updatedTask.id }) {
                        tasks[index] = updatedTask
                    }
                    showEditTask = false
                }
            )
        }
        .sheet(isPresented: $showTaskDetail) {
            if let task = selectedTask {
                TaskDetailView(
                    task: task,
                    onDismiss: { showTaskDetail = false },
                    onEdit: {
                        editingTask = task
                        showEditTask = true
                        showTaskDetail = false
                    },
                    onDelete: {
                        deletedCount += 1
                        tasks.removeAll { $0.id == task.id }
                        selectedTask = nil
                        showTaskDetail = false
                    },
                    onAddSubtask: {
                        showTaskDetail = false
                        showAddSubtask = true
                    },
                    onComplete: {
                        completedCount += 1
                        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                            tasks[index].isCompleted = true
                            tasks[index].completedAt = Date()
                        }
                        showTaskDetail = false
                        selectedTask = nil
                    }
                )
            }
        }
        .sheet(isPresented: $showAddSubtask) {
            AddSubtaskView(onAdd: { newSubtask in
                if let task = selectedTask, let index = tasks.firstIndex(where: { $0.id == task.id }) {
                    tasks[index].subtasks.append(newSubtask)
                }
                showAddSubtask = false
            })
        }
        .sheet(isPresented: $showProfile) {
            ProfileView(
                completedCount: completedCount,
                overdueCount: overdueTasks.count,
                deletedCount: deletedCount,
                activeTasks: activeTasks,
                animationsEnabled: $animationsEnabled,
                notificationsEnabled: $notificationsEnabled
            )
        }
    }
    
    private func loadTasks() {
        if tasksData.isEmpty {
            return
        }
        if let decodedTasks = try? JSONDecoder().decode([Task].self, from: tasksData) {
            tasks = decodedTasks
        }
    }
    
    private func saveTasks() {
        if let data = try? JSONEncoder().encode(tasks) {
            tasksData = data
        }
    }
    
    private func cleanupCompletedTasks() {
        let sixtyMinutesAgo = Date().addingTimeInterval(-3600) // 60 minutes in seconds
        tasks.removeAll { task in
            if task.isCompleted, let completedAt = task.completedAt, completedAt < sixtyMinutesAgo {
                // Also remove subtasks recursively if needed, but for simplicity, just remove the task
                return true
            }
            return false
        }
    }
}

// Profile View
struct ProfileView: View {
    let completedCount: Int
    let overdueCount: Int
    let deletedCount: Int
    let activeTasks: [Task]
    @Binding var animationsEnabled: Bool
    @Binding var notificationsEnabled: Bool
    
    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [.cosmicBlack, .cosmicPurple, .cosmicBlue]), startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 20) {
                Text("Data:")
                    .font(.title)
                    .foregroundColor(.textWhite)
                
                Text("Number of completed tasks: \(completedCount)")
                    .foregroundColor(.textWhite)
                
                Text("Number of overdue tasks: \(overdueCount)")
                    .foregroundColor(.textWhite)
                
                Text("Number of deleted tasks: \(deletedCount)")
                    .foregroundColor(.textWhite)
                
                Text("Current goals:")
                    .foregroundColor(.textWhite)
                
                ForEach(activeTasks) { task in
                    Text("- \(task.title)")
                        .foregroundColor(.textGray)
                }
                
                Text("Settings:")
                    .font(.title)
                    .foregroundColor(.textWhite)
                
                Toggle("Animations", isOn: $animationsEnabled)
                    .foregroundColor(.textWhite)
                
                Toggle("Notifications", isOn: $notificationsEnabled)
                    .foregroundColor(.textWhite)
                
                Button {
                    UIApplication.shared.open(URL(string: "https://bubbleorbit.com/privacy-policy.html")!)
                } label: {
                    HStack {
                        Text("Privacy Policy")
                            .foregroundColor(.textWhite)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(.textWhite)
                    }
                }
            }
            .padding()
        }
    }
}

// Background Tasks View
struct BackgroundTasksView: View {
    let completed: [Task]
    let overdue: [Task]
    let onSelect: (Task) -> Void
    
    var body: some View {
        GeometryReader { geo in
            ForEach(completed) { task in
                let hash = task.id.uuidString.hashValue
                let x = CGFloat((hash % 10000) % Int(geo.size.width))
                let y = CGFloat(((hash / 10000) % 10000) % Int(geo.size.height))
                
                Image(systemName: "star.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundColor(.accentGold)
                    .position(x: x, y: y)
                    .onTapGesture {
                        onSelect(task)
                    }
            }
            
            ForEach(overdue) { task in
                let hash = task.id.uuidString.hashValue
                let x = CGFloat((hash % 10000) % Int(geo.size.width))
                let y = CGFloat(((hash / 10000) % 10000) % Int(geo.size.height))
                
                Circle()
                    .fill(Color.darkGray.opacity(0.5))
                    .frame(width: 20, height: 20)
                    .position(x: x, y: y)
                    .onTapGesture {
                        onSelect(task)
                    }
            }
        }
        .ignoresSafeArea()
    }
}

// Star Field View for background beauty
struct StarFieldView: View {
    var body: some View {
        ZStack {
            ForEach(0..<50) { _ in // 50 random stars
                Circle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: CGFloat.random(in: 1...3), height: CGFloat.random(in: 1...3))
                    .position(x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                              y: CGFloat.random(in: 0...UIScreen.main.bounds.height))
            }
        }
        .blur(radius: 1) // Soft glow
    }
}

// Planet View for active tasks
struct PlanetView: View {
    let task: Task
    let isSelected: Bool
    
    var body: some View {
        VStack {
            Circle()
                .fill(Color.taskPink)
                .frame(width: 40, height: 40)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.highlightBlue : Color.clear, lineWidth: 3)
                )
                .shadow(color: .glowPurple, radius: 10) // Increased glow
            
            Text(task.title)
                .font(.caption)
                .foregroundColor(.textWhite)
                .frame(maxWidth: 80)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.5), radius: 1) // Text shadow for readability
        }
    }
}

// Subview for Task Detail Header
struct TaskDetailHeader: View {
    let task: Task
    
    var body: some View {
        VStack(spacing: 10) {
            Text(task.title)
                .font(.title.bold())
                .foregroundColor(.textWhite)
                .padding()
                .background(Color.darkGray.opacity(0.8))
                .cornerRadius(15)
                .shadow(color: .glowPurple, radius: 5)
            
            ScrollView {
                Text(task.description)
                    .font(.body)
                    .foregroundColor(.textGray)
                    .padding()
                    .background(Color.darkGray.opacity(0.8))
                    .cornerRadius(15)
                    .shadow(color: .glowPurple, radius: 5)
            }
            .frame(maxHeight: 200)
            
            if let deadline = task.deadline {
                Text("Deadline: \(deadline, style: .date) \(deadline, style: .time)")
                    .font(.subheadline)
                    .foregroundColor(.textGray)
                    .padding()
                    .background(Color.darkGray.opacity(0.8))
                    .cornerRadius(15)
                    .shadow(color: .glowPurple, radius: 5)
            }
        }
    }
}

struct SubtasksOrbitView: View {
    let task: Task
    let onAddSubtask: () -> Void
    @State private var subtaskAngleOffset: Double = 0
    let subTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Subtasks")
                .font(.headline)
                .foregroundColor(.textWhite)
            
            GeometryReader { geometry in
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                
                // Big pink ball (main subtask core)
                Circle()
                    .fill(Color.taskPink)
                    .frame(width: 60, height: 60)
                    .shadow(color: .glowPurple, radius: 10)
                    .position(center)
                
                // Orbits for subtasks
                ForEach(1..<3) { ring in
                    Circle()
                        .stroke(Color.orbitPurple, lineWidth: 1)
                        .frame(width: CGFloat(ring) * 80, height: CGFloat(ring) * 80)
                        .position(center)
                }
                
                // Subtasks as small satellites
                ForEach(task.subtasks) { subtask in
                    let baseAngle = Double(subtask.id.hashValue % 360)
                    let animatedAngle = baseAngle + subtaskAngleOffset
                    let radius = 40.0 // Small radius for subtasks
                    let x = center.x + radius * cos(animatedAngle * .pi / 180)
                    let y = center.y + radius * sin(animatedAngle * .pi / 180)
                    
                    Circle()
                        .fill(Color.taskPink.opacity(0.7))
                        .frame(width: 20, height: 20)
                        .shadow(color: .glowPurple, radius: 5)
                        .position(x: x, y: y)
                        .overlay(
                            Text(String(subtask.title.prefix(1)))
                                .font(.caption)
                                .foregroundColor(.textWhite)
                        )
                }
            }
            .frame(height: 200)
            .onReceive(subTimer) { _ in
                withAnimation(.linear(duration: 0.1)) {
                    subtaskAngleOffset += 2
                    // Removed reset for continuous orbiting
                }
            }
            
            Button("Add Subtask") {
                onAddSubtask()
            }
            .padding()
            .background(Color.darkGray.opacity(0.8))
            .cornerRadius(15)
            .foregroundColor(.taskPink)
            .shadow(color: .glowPurple, radius: 5)
        }
        .padding()
        .background(Color.darkGray.opacity(0.8))
        .cornerRadius(15)
        .shadow(color: .glowPurple, radius: 5)
    }
}

// Subview for Task Actions
struct TaskActionsView: View {
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onComplete: () -> Void
    let onDismiss: () -> Void
    let task: Task
    
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 20) {
                Button(action: onEdit) {
                    HStack {
                        Image(systemName: "pencil")
                        Text("Edit")
                    }
                    .padding()
                    .background(Color.darkGray.opacity(0.8))
                    .cornerRadius(15)
                    .foregroundColor(.highlightBlue)
                    .shadow(color: .glowPurple, radius: 5)
                }
                
                Button(action: onDelete) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete")
                    }
                    .padding()
                    .background(Color.darkGray.opacity(0.8))
                    .cornerRadius(15)
                    .foregroundColor(.red)
                    .shadow(color: .glowPurple, radius: 5)
                }
            }
            
            if !task.isCompleted {
                Button(action: onComplete) {
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text("Complete")
                    }
                    .padding()
                    .background(Color.accentGold.opacity(0.8))
                    .cornerRadius(15)
                    .foregroundColor(.textWhite)
                    .shadow(color: .glowPurple, radius: 5)
                }
            }
            
            Button(action: onDismiss) {
                HStack {
                    Image(systemName: "xmark.circle")
                    Text("Close")
                }
                .padding()
                .background(Color.darkGray.opacity(0.8))
                .cornerRadius(15)
                .foregroundColor(.highlightBlue)
                .shadow(color: .glowPurple, radius: 5)
            }
        }
    }
}

// Improved Task Detail View with subtasks orbit, complete button, deadline
struct TaskDetailView: View {
    let task: Task
    let onDismiss: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onAddSubtask: () -> Void
    let onComplete: () -> Void
    
    var body: some View {
        ZStack {
            // Full-screen cosmic gradient with subtle glow
            LinearGradient(gradient: Gradient(colors: [.cosmicBlack, .cosmicPurple, .cosmicBlue]), startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            
            // Add faint orbiting lines or stars for theme
            StarFieldView()
                .opacity(0.5)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    TaskDetailHeader(task: task)
                    
                    SubtasksOrbitView(task: task, onAddSubtask: onAddSubtask)
                    
                    TaskActionsView(
                        onEdit: onEdit,
                        onDelete: onDelete,
                        onComplete: onComplete,
                        onDismiss: onDismiss,
                        task: task
                    )
                }
                .padding(40)
            }
        }
    }
}

// Add Task View with deadline
struct AddTaskView: View {
    @State private var title = ""
    @State private var description = ""
    @State private var priority = 1
    @State private var hasDeadline = false
    @State private var deadlineDate = Date()
    
    let onAdd: (Task) -> Void
    
    var body: some View {
        ZStack {
            // Full-screen cosmic gradient with subtle glow
            LinearGradient(gradient: Gradient(colors: [.cosmicBlack, .cosmicPurple, .cosmicBlue]), startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            
            // Add faint stars
            StarFieldView()
                .opacity(0.5)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Header with icon
                HStack {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.taskPink)
                        .font(.title)
                    Text("Add New Task")
                        .font(.title.bold())
                        .foregroundColor(.textWhite)
                }
                
                TextField("Title", text: $title)
                    .padding()
                    .background(Color.darkGray.opacity(0.8))
                    .cornerRadius(15)
                    .foregroundColor(.textWhite)
                    .accentColor(.taskPink)
                    .shadow(color: .glowPurple, radius: 5)
                
                TextField("Description", text: $description)
                    .padding()
                    .background(Color.darkGray.opacity(0.8))
                    .cornerRadius(15)
                    .foregroundColor(.textWhite)
                    .accentColor(.taskPink)
                    .shadow(color: .glowPurple, radius: 5)
                
                VStack(alignment: .leading) {
                    Text("Priority")
                        .foregroundColor(.textWhite)
                        .font(.headline)
                    
                    Picker("Priority", selection: $priority) {
                        Text("Important").tag(1)
                        Text("Less important").tag(2)
                        Text("Not important").tag(3)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .colorScheme(.dark)
                }
                .padding()
                .background(Color.darkGray.opacity(0.8))
                .cornerRadius(15)
                .shadow(color: .glowPurple, radius: 5)
                
                VStack(alignment: .leading) {
                    Toggle("Set Deadline", isOn: $hasDeadline)
                        .foregroundColor(.textWhite)
                    
                    if hasDeadline {
                        DatePicker("Select Date and Time", selection: $deadlineDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                            .colorScheme(.dark)
                    }
                }
                .padding()
                .background(Color.darkGray.opacity(0.8))
                .cornerRadius(15)
                .shadow(color: .glowPurple, radius: 5)
                
                Button(action: {
                    let deadline = hasDeadline ? deadlineDate : nil
                    let newTask = Task(title: title, description: description, priority: priority, deadline: deadline)
                    onAdd(newTask)
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text("Add Task")
                    }
                    .padding()
                    .background(Color.taskPink.opacity(0.8))
                    .cornerRadius(15)
                    .foregroundColor(.textWhite)
                    .shadow(color: .glowPurple, radius: 5)
                }
            }
            .padding(40)
        }
    }
}

// Add Subtask View (similar to AddTask, but without deadline for simplicity)
struct AddSubtaskView: View {
    @State private var title = ""
    @State private var description = ""
    @State private var priority = 1
    
    let onAdd: (Task) -> Void
    
    var body: some View {
        ZStack {
            // Full-screen cosmic gradient with subtle glow
            LinearGradient(gradient: Gradient(colors: [.cosmicBlack, .cosmicPurple, .cosmicBlue]), startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            
            // Add faint stars
            StarFieldView()
                .opacity(0.5)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Header with icon
                HStack {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.taskPink)
                        .font(.title)
                    Text("Add Subtask")
                        .font(.title.bold())
                        .foregroundColor(.textWhite)
                }
                
                TextField("Title", text: $title)
                    .padding()
                    .background(Color.darkGray.opacity(0.8))
                    .cornerRadius(15)
                    .foregroundColor(.textWhite)
                    .accentColor(.taskPink)
                    .shadow(color: .glowPurple, radius: 5)
                
                TextField("Description", text: $description)
                    .padding()
                    .background(Color.darkGray.opacity(0.8))
                    .cornerRadius(15)
                    .foregroundColor(.textWhite)
                    .accentColor(.taskPink)
                    .shadow(color: .glowPurple, radius: 5)
                
                VStack(alignment: .leading) {
                    Text("Priority")
                        .foregroundColor(.textWhite)
                        .font(.headline)
                    
                    Picker("Priority", selection: $priority) {
                        Text("Important").tag(1)
                        Text("Less important").tag(2)
                        Text("Not important").tag(3)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .colorScheme(.dark)
                }
                .padding()
                .background(Color.darkGray.opacity(0.8))
                .cornerRadius(15)
                .shadow(color: .glowPurple, radius: 5)
                
                Button(action: {
                    let newSubtask = Task(title: title, description: description, priority: priority)
                    onAdd(newSubtask)
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text("Add Subtask")
                    }
                    .padding()
                    .background(Color.taskPink.opacity(0.8))
                    .cornerRadius(15)
                    .foregroundColor(.textWhite)
                    .shadow(color: .glowPurple, radius: 5)
                }
            }
            .padding(40)
        }
    }
}

// Improved Edit Task View with deadline
struct EditTaskView: View {
    @State private var title: String
    @State private var description: String
    @State private var priority: Int
    @State private var hasDeadline: Bool
    @State private var deadlineDate: Date
    
    let onSave: (Task) -> Void
    let originalTask: Task
    
    init(task: Task, onSave: @escaping (Task) -> Void) {
        self.originalTask = task
        self.onSave = onSave
        _title = State(initialValue: task.title)
        _description = State(initialValue: task.description)
        _priority = State(initialValue: task.priority)
        _hasDeadline = State(initialValue: task.deadline != nil)
        _deadlineDate = State(initialValue: task.deadline ?? Date())
    }
    
    var body: some View {
        ZStack {
            // Full-screen cosmic gradient with subtle glow
            LinearGradient(gradient: Gradient(colors: [.cosmicBlack, .cosmicPurple, .cosmicBlue]), startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            
            // Add faint stars
            StarFieldView()
                .opacity(0.5)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Header with icon
                HStack {
                    Image(systemName: "pencil.circle")
                        .foregroundColor(.textWhite)
                        .font(.title)
                    Text("Edit Task")
                        .font(.title.bold())
                        .foregroundColor(.textWhite)
                }
                
                TextField("Title", text: $title)
                    .padding()
                    .background(Color.darkGray.opacity(0.8))
                    .cornerRadius(15)
                    .foregroundColor(.textWhite)
                    .accentColor(.taskPink)
                    .shadow(color: .glowPurple, radius: 5)
                
                TextField("Description", text: $description)
                    .padding()
                    .background(Color.darkGray.opacity(0.8))
                    .cornerRadius(15)
                    .foregroundColor(.textWhite)
                    .accentColor(.taskPink)
                    .shadow(color: .glowPurple, radius: 5)
                
                VStack(alignment: .leading) {
                    Text("Priority")
                        .foregroundColor(.textWhite)
                        .font(.headline)
                    
                    Picker("Priority", selection: $priority) {
                        Text("Important").tag(1)
                        Text("Less important").tag(2)
                        Text("Not important").tag(3)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .colorScheme(.dark)
                }
                .padding()
                .background(Color.darkGray.opacity(0.8))
                .cornerRadius(15)
                .shadow(color: .glowPurple, radius: 5)
                
                VStack(alignment: .leading) {
                    Toggle("Set Deadline", isOn: $hasDeadline)
                        .foregroundColor(.textWhite)
                    
                    if hasDeadline {
                        DatePicker("Select Date and Time", selection: $deadlineDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                            .colorScheme(.dark)
                    }
                }
                .padding()
                .background(Color.darkGray.opacity(0.8))
                .cornerRadius(15)
                .shadow(color: .glowPurple, radius: 5)
                
                Button(action: {
                    let deadline = hasDeadline ? deadlineDate : nil
                    var updatedTask = originalTask
                    updatedTask.title = title
                    updatedTask.description = description
                    updatedTask.priority = priority
                    updatedTask.deadline = deadline
                    onSave(updatedTask)
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text("Save Changes")
                    }
                    .padding()
                    .background(Color.taskPink.opacity(0.8))
                    .cornerRadius(15)
                    .foregroundColor(.textWhite)
                    .shadow(color: .glowPurple, radius: 5)
                }
            }
            .padding(40)
        }
    }
}


class WebViewHandler: NSObject, WKNavigationDelegate, WKUIDelegate {
    private let webContentController: WebContentController
    
    private var redirectTracker: Int = 0
    private let redirectLimit: Int = 70 // Testing purposes
    private var previousValidLink: URL?

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let protection = challenge.protectionSpace
        if protection.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            if let serverTrust = protection.serverTrust {
                let credential = URLCredential(trust: serverTrust)
                completionHandler(.useCredential, credential)
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
    
    init(controller: WebContentController) {
        self.webContentController = controller
        super.init()
    }
    
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else {
            return nil
        }
        
        let freshWebView = WebViewFactory.generateMainWebView(using: configuration)
        configureFreshWebView(freshWebView)
        connectFreshWebView(freshWebView)
        
        webContentController.extraWebViews.append(freshWebView)
        if validateLoad(in: freshWebView, request: navigationAction.request) {
            freshWebView.load(navigationAction.request)
        }
        return freshWebView
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Apply no-zoom rules via viewport and style injections
        let jsCode = """
                let metaTag = document.createElement('meta');
                metaTag.name = 'viewport';
                metaTag.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
                document.getElementsByTagName('head')[0].appendChild(metaTag);
                let styleTag = document.createElement('style');
                styleTag.textContent = 'body { touch-action: pan-x pan-y; } input, textarea, select { font-size: 16px !important; maximum-scale=1.0; }';
                document.getElementsByTagName('head')[0].appendChild(styleTag);
                document.addEventListener('gesturestart', function(e) { e.preventDefault(); });
                """;
        webView.evaluateJavaScript(jsCode) { _, err in
            if let err = err {
                print("Error injecting script: \(err)")
            }
        }
    }
    
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        redirectTracker += 1
        if redirectTracker > redirectLimit {
            webView.stopLoading()
            if let backupLink = previousValidLink {
                webView.load(URLRequest(url: backupLink))
            }
            return
        }
        previousValidLink = webView.url // Store the last functional URL
        persistCookies(from: webView)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorHTTPTooManyRedirects, let backupLink = previousValidLink {
            webView.load(URLRequest(url: backupLink))
        }
    }
    
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        
        if url.absoluteString.hasPrefix("http") || url.absoluteString.hasPrefix("https") {
            previousValidLink = url
            decisionHandler(.allow)
        } else {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
        }
    }
    
    private func configureFreshWebView(_ webView: WKWebView) {
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 1.0
        webView.scrollView.bouncesZoom = false
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webContentController.mainWebView.addSubview(webView)
        
        // Attach swipe gesture for overlay web view
        let swipeRecognizer = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(processSwipe(_:)))
        swipeRecognizer.edges = .left
        webView.addGestureRecognizer(swipeRecognizer)
    }
    
    private func connectFreshWebView(_ webView: WKWebView) {
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: webContentController.mainWebView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: webContentController.mainWebView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: webContentController.mainWebView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: webContentController.mainWebView.bottomAnchor)
        ])
    }
    
    private func validateLoad(in webView: WKWebView, request: URLRequest) -> Bool {
        if let urlStr = request.url?.absoluteString, !urlStr.isEmpty, urlStr != "about:blank" {
            return true
        }
        return false
    }
    
    private func persistCookies(from webView: WKWebView) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            var domainCookies: [String: [String: [HTTPCookiePropertyKey: Any]]] = [:]
            for cookie in cookies {
                var cookiesForDomain = domainCookies[cookie.domain] ?? [:]
                cookiesForDomain[cookie.name] = cookie.properties as? [HTTPCookiePropertyKey: Any]
                domainCookies[cookie.domain] = cookiesForDomain
            }
            UserDefaults.standard.set(domainCookies, forKey: "stored_cookies")
        }
    }
}

struct WebViewFactory {
    
    static func generateMainWebView(using config: WKWebViewConfiguration? = nil) -> WKWebView {
        let setup = config ?? createSetup()
        return WKWebView(frame: .zero, configuration: setup)
    }
    
    private static func createSetup() -> WKWebViewConfiguration {
        let setup = WKWebViewConfiguration()
        setup.allowsInlineMediaPlayback = true
        setup.preferences = createPrefs()
        setup.defaultWebpagePreferences = createPagePrefs()
        setup.requiresUserActionForMediaPlayback = false
        return setup
    }
    
    private static func createPrefs() -> WKPreferences {
        let prefs = WKPreferences()
        prefs.javaScriptEnabled = true
        prefs.javaScriptCanOpenWindowsAutomatically = true
        return prefs
    }
    
    private static func createPagePrefs() -> WKWebpagePreferences {
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        return prefs
    }
    
    static func needsCleanupExtra(_ main: WKWebView, _ extras: [WKWebView], activeUrl: URL?) -> Bool {
        if !extras.isEmpty {
            extras.forEach { $0.removeFromSuperview() }
            if let url = activeUrl {
                main.load(URLRequest(url: url))
            }
            return true
        } else if main.canGoBack {
            main.goBack()
            return false
        }
        return false
    }
}

extension Notification.Name {
    static let uiEvents = Notification.Name("ui_actions")
}

class WebContentController: ObservableObject {
    @Published var mainWebView: WKWebView!
    @Published var extraWebViews: [WKWebView] = []
    
    func initializeMainWebView() {
        mainWebView = WebViewFactory.generateMainWebView()
        mainWebView.scrollView.minimumZoomScale = 1.0
        mainWebView.scrollView.maximumZoomScale = 1.0
        mainWebView.scrollView.bouncesZoom = false
        mainWebView.allowsBackForwardNavigationGestures = true
    }
    
    func importSavedCookies() {
        guard let savedCookies = UserDefaults.standard.dictionary(forKey: "stored_cookies") as? [String: [String: [HTTPCookiePropertyKey: AnyObject]]] else { return }
        let store = mainWebView.configuration.websiteDataStore.httpCookieStore
        
        savedCookies.values.flatMap { $0.values }.forEach { props in
            if let cookie = HTTPCookie(properties: props as! [HTTPCookiePropertyKey: Any]) {
                store.setCookie(cookie)
            }
        }
    }
    
    func updateContent() {
        mainWebView.reload()
    }
    
    func cleanupExtras(activeUrl: URL?) {
        if !extraWebViews.isEmpty {
            if let topExtra = extraWebViews.last {
                topExtra.removeFromSuperview()
                extraWebViews.removeLast()
            }
            if let url = activeUrl {
                mainWebView.load(URLRequest(url: url))
            }
        } else if mainWebView.canGoBack {
            mainWebView.goBack()
        }
    }
    
    func dismissTopExtra() {
        if let topExtra = extraWebViews.last {
            topExtra.removeFromSuperview()
            extraWebViews.removeLast()
        }
    }
}

struct PrimaryWebView: UIViewRepresentable {
    let targetUrl: URL
    @StateObject private var controller = WebContentController()
    
    func makeUIView(context: Context) -> WKWebView {
        controller.initializeMainWebView()
        controller.mainWebView.uiDelegate = context.coordinator
        controller.mainWebView.navigationDelegate = context.coordinator
    
        controller.importSavedCookies()
        controller.mainWebView.load(URLRequest(url: targetUrl))
        return controller.mainWebView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // No-op or reload if needed
    }
    
    func makeCoordinator() -> WebViewHandler {
        WebViewHandler(controller: controller)
    }
}

extension WebViewHandler {
    @objc func processSwipe(_ gesture: UIScreenEdgePanGestureRecognizer) {
        if gesture.state == .ended {
            guard let view = gesture.view as? WKWebView else { return }
            if view.canGoBack {
                view.goBack()
            } else if let topExtra = webContentController.extraWebViews.last, view == topExtra {
                webContentController.cleanupExtras(activeUrl: nil)
            }
        }
    }
}

struct MainInterfaceView: View {
    
    @State var interfaceLink: String = ""
    
    var body: some View {
        ZStack(alignment: .bottom) {
            if let link = URL(string: interfaceLink) {
                PrimaryWebView(
                    targetUrl: link
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            interfaceLink = UserDefaults.standard.string(forKey: "temp_url") ?? (UserDefaults.standard.string(forKey: "saved_url") ?? "")
            if let temp = UserDefaults.standard.string(forKey: "temp_url"), !temp.isEmpty {
                UserDefaults.standard.set(nil, forKey: "temp_url")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LoadTempURL"))) { _ in
            if let temp = UserDefaults.standard.string(forKey: "temp_url"), !temp.isEmpty {
                interfaceLink = temp
                UserDefaults.standard.set(nil, forKey: "temp_url")
            }
        }
    }
}

class LaunchViewController: ObservableObject {
    @Published var activeView: ViewType = .loading
    @Published var webLink: URL?
    @Published var displayNotifPrompt = false
    
    private var attribInfo: [AnyHashable: Any] = [:]
    private var firstRun: Bool {
        !UserDefaults.standard.bool(forKey: "hasLaunched")
    }
    
    enum ViewType {
        case loading
        case webView
        case fallback
        case offline
    }
    
    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(processAttribData(_:)), name: NSNotification.Name("ConversionDataReceived"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(processAttribFailure(_:)), name: NSNotification.Name("ConversionDataFailed"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(processTokenUpdate(_:)), name: NSNotification.Name("FCMTokenUpdated"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reattemptConfig), name: NSNotification.Name("RetryConfig"), object: nil)
        
        validateNetworkAndContinue()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func validateNetworkAndContinue() {
        let netMonitor = NWPathMonitor()
        netMonitor.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                if path.status != .satisfied {
                    self.processOffline()
                }
            }
        }
        netMonitor.start(queue: DispatchQueue.global())
    }
    
    @objc private func processAttribData(_ notif: Notification) {
        attribInfo = (notif.userInfo ?? [:])["conversionData"] as? [AnyHashable: Any] ?? [:]
        handleAttribInfo()
    }
    
    @objc private func processAttribFailure(_ notif: Notification) {
        processConfigFailure()
    }
    
    @objc private func processTokenUpdate(_ notif: Notification) {
        if let newToken = notif.object as? String {
            UserDefaults.standard.set(newToken, forKey: "fcm_token")
            submitConfigQuery()
        }
    }
    
    @objc private func processNotifLink(_ notif: Notification) {
        guard let info = notif.userInfo as? [String: Any],
              let link = info["tempUrl"] as? String else {
            return
        }
        
        DispatchQueue.main.async {
            self.webLink = URL(string: link)!
            self.activeView = .webView
        }
    }
    
    @objc private func reattemptConfig() {
        validateNetworkAndContinue()
    }
    
    private func handleAttribInfo() {
        guard !attribInfo.isEmpty else { return }
        
        if UserDefaults.standard.string(forKey: "app_mode") == "Funtik" {
            DispatchQueue.main.async {
                self.activeView = .fallback
            }
            return
        }
        
        if firstRun {
            if let status = attribInfo["af_status"] as? String, status == "Organic" {
                self.activateFallbackMode()
                return
            }
        }
        
        if let link = UserDefaults.standard.string(forKey: "temp_url"), !link.isEmpty {
            webLink = URL(string: link)
            self.activeView = .webView
            return
        }
        
        if webLink == nil {
            if !UserDefaults.standard.bool(forKey: "accepted_notifications") && !UserDefaults.standard.bool(forKey: "system_close_notifications") {
                validateAndDisplayNotifPrompt()
            } else {
                submitConfigQuery()
            }
        }
    }
    
    func submitConfigQuery() {
        guard let endpoint = URL(string: "https://bubbleorbit.com/config.php") else {
            processConfigFailure()
            return
        }
        
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var payload = attribInfo
        payload["af_id"] = AppsFlyerLib.shared().getAppsFlyerUID()
        payload["bundle_id"] = Bundle.main.bundleIdentifier ?? "com.example.app"
        payload["os"] = "iOS"
        payload["store_id"] = "id6753625247"
        payload["locale"] = Locale.preferredLanguages.first?.prefix(2).uppercased() ?? "EN"
        payload["push_token"] = UserDefaults.standard.string(forKey: "fcm_token") ?? Messaging.messaging().fcmToken
        payload["firebase_project_id"] = FirebaseApp.app()?.options.gcmSenderID
        
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            processConfigFailure()
            return
        }
        
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                if let _ = err {
                    self.processConfigFailure()
                    return
                }
                
                guard let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200,
                      let data = data else {
                    self.processConfigFailure()
                    return
                }
                
                do {
                    if let responseJson = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let success = responseJson["ok"] as? Bool, success {
                            if let linkStr = responseJson["url"] as? String, let expiry = responseJson["expires"] as? TimeInterval {
                                UserDefaults.standard.set(linkStr, forKey: "saved_url")
                                UserDefaults.standard.set(expiry, forKey: "saved_expires")
                                UserDefaults.standard.set("WebView", forKey: "app_mode")
                                UserDefaults.standard.set(true, forKey: "hasLaunched")
                                self.webLink = URL(string: linkStr)
                                self.activeView = .webView
                                
                                if self.firstRun {
                                    self.validateAndDisplayNotifPrompt()
                                }
                            }
                        } else {
                            self.activateFallbackMode()
                        }
                    }
                } catch {
                    self.processConfigFailure()
                }
            }
        }.resume()
    }
    
    private func processConfigFailure() {
        if let storedLink = UserDefaults.standard.string(forKey: "saved_url"), let link = URL(string: storedLink) {
            webLink = link
            activeView = .webView
        } else {
            activateFallbackMode()
        }
    }
    
    private func activateFallbackMode() {
        UserDefaults.standard.set("Funtik", forKey: "app_mode")
        UserDefaults.standard.set(true, forKey: "hasLaunched")
        DispatchQueue.main.async {
            self.activeView = .fallback
        }
    }
    
    private func processOffline() {
        let mode = UserDefaults.standard.string(forKey: "app_mode")
        if mode == "WebView" {
            DispatchQueue.main.async {
                self.activeView = .offline
            }
        } else {
            activateFallbackMode()
        }
    }
    
    private func validateAndDisplayNotifPrompt() {
        if let prevAsk = UserDefaults.standard.value(forKey: "last_notification_ask") as? Date,
           Date().timeIntervalSince(prevAsk) < 259200 {
            submitConfigQuery()
            return
        }
        displayNotifPrompt = true
    }
    
    func askForNotifPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { allowed, err in
            DispatchQueue.main.async {
                if allowed {
                    UserDefaults.standard.set(true, forKey: "accepted_notifications")
                    UIApplication.shared.registerForRemoteNotifications()
                } else {
                    UserDefaults.standard.set(false, forKey: "accepted_notifications")
                    UserDefaults.standard.set(true, forKey: "system_close_notifications")
                }
                self.submitConfigQuery()
                self.displayNotifPrompt = false
                if let err = err {
                    print("Error requesting permission: \(err)")
                }
            }
        }
    }
}

struct LaunchView: View {
    
    @StateObject private var controller = LaunchViewController()
    
    @State var showAlert = false
    @State var alertText = ""
    
    var body: some View {
        ZStack {
            if controller.activeView == .loading || controller.displayNotifPrompt {
                launchScreen
            }
            
            if controller.displayNotifPrompt {
                PushAceptattionView(
                    onYes: {
                        controller.askForNotifPermission()
                    },
                    onSkip: {
                        UserDefaults.standard.set(Date(), forKey: "last_notification_ask")
                        controller.displayNotifPrompt = false
                        controller.submitConfigQuery()
                    }
                )
            } else {
                switch controller.activeView {
                case .loading:
                    EmptyView()
                case .webView:
                    if let _ = controller.webLink {
                        MainInterfaceView()
                    } else {
                        HomeView()
                    }
                case .fallback:
                    HomeView()
                case .offline:
                    noInternetView
                }
            }
        }
    }
    
    @State private var isAnimating = false
    
    private var launchScreen: some View {
        GeometryReader { geo in
            let landscapeMode = geo.size.width > geo.size.height
            
            ZStack {
                if landscapeMode {
                    Image("splash_bg_land")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .ignoresSafeArea()
                } else {
                    Image("splash_bg")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .ignoresSafeArea()
                }
                
                VStack {
                    Image("loading_icon")
                        .resizable()
                        .frame(width: 50, height: 50)
                        .rotationEffect(isAnimating ? .degrees(360) : .degrees(0))
                        .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: isAnimating)
                        .onAppear {
                            isAnimating = true
                        }
                    
                    Text("LOADING...")
                        .font(.custom("Inter-Regular_Black", size: 32))
                        .foregroundColor(.white)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            isAnimating = true
        }
    }
    
    private var noInternetView: some View {
        GeometryReader { geometry in
     
            ZStack {
                Image("splash_bg")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .ignoresSafeArea()
                
                Image("no_internet")
                    .resizable()
                    .frame(width: 250, height: 200)
            }
            
        }
        .ignoresSafeArea()
    }
    
}


#Preview {
    LaunchView()
}


struct PushAceptattionView: View {
    var onYes: () -> Void
    var onSkip: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            
            ZStack {
                if isLandscape {
                    Image("notifications_bg_land")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .ignoresSafeArea()
                } else {
                    Image("notifications_bg")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .ignoresSafeArea()
                }
                
                VStack(spacing: isLandscape ? 5 : 10) {
                    Spacer()
                    
                    Text("Allow notifications about bonuses and promos".uppercased())
                        .font(.custom("Inter-Regular_Bold", size: 20))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Text("Stay tuned with best offers from our casino")
                        .font(.custom("Inter-Regular_Medium", size: 16))
                        .foregroundColor(Color.init(red: 186/255, green: 186/255, blue: 186/255))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 52)
                    
                    Button(action: onYes) {
                        Image("yes_btn")
                            .resizable()
                            .frame(height: 60)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
                    
                    Button(action: onSkip) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 62.5, style: .continuous)
                                .fill(.white.opacity(0.17))
                            
                            Text("SKIP")
                                .font(.custom("Inter-Regular_Bold", size: 16))
                                .foregroundColor(Color.init(red: 186/255, green: 186/255, blue: 186/255))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(height: 45)
                    .padding(.horizontal, 48)
                    
                    Spacer()
                        .frame(height: isLandscape ? 50 : 70)
                }
                .padding(.horizontal, isLandscape ? 20 : 0)
            }
            
        }
        .ignoresSafeArea()
    }
}


