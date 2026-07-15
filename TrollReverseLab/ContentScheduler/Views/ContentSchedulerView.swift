import SwiftUI

// MARK: - Content Scheduler View

struct ContentSchedulerView: View {
    @EnvironmentObject var manager: ContentSchedulerManager
    @State private var showAddSheet = false
    @State private var showEditSheet = false
    @State private var editingItem: ScheduleItem?

    var body: some View {
        NavigationView {
            List {
                // Stats section
                Section(header: Text("排期概览")) {
                    let stats = manager.stats
                    HStack {
                        StatBadge(title: "已计划", count: stats.planned, color: .blue)
                        StatBadge(title: "进行中", count: stats.inProgress, color: .orange)
                        StatBadge(title: "已完成", count: stats.completed, color: .green)
                        StatBadge(title: "已逾期", count: stats.overdue, color: .red)
                    }

                    if stats.total > 0 {
                        VStack(alignment: .leading) {
                            Text("完成率")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ProgressView(value: stats.completionRate)
                                .progressViewStyle(LinearProgressViewStyle())
                        }
                    }
                }

                // Today
                if !manager.todayItems.isEmpty {
                    Section(header: Text("今日待办")) {
                        ForEach(manager.todayItems) { item in
                            ScheduleRowView(item: item)
                                .onTapGesture {
                                    editingItem = item
                                    showEditSheet = true
                                }
                        }
                    }
                }

                // Overdue
                if !manager.overdueItems.isEmpty {
                    Section(header: Text("已逾期")) {
                        ForEach(manager.overdueItems) { item in
                            ScheduleRowView(item: item, isOverdue: true)
                                .onTapGesture {
                                    editingItem = item
                                    showEditSheet = true
                                }
                        }
                    }
                }

                // Upcoming
                if !manager.upcomingItems.isEmpty {
                    Section(header: Text("即将到来")) {
                        ForEach(manager.upcomingItems) { item in
                            ScheduleRowView(item: item)
                                .onTapGesture {
                                    editingItem = item
                                    showEditSheet = true
                                }
                        }
                    }
                }

                // All items
                Section(header: Text("全部排期")) {
                    if manager.items.isEmpty {
                        Text("暂无排期，点击右上角添加")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    ForEach(manager.items) { item in
                        ScheduleRowView(item: item)
                            .onTapGesture {
                                editingItem = item
                                showEditSheet = true
                            }
                    }
                    .onDelete(perform: deleteItem)
                }

                // Info section
                Section(footer: Text("离线排期提醒，仅做个人创作排期管理，不包含自动发帖功能。所有发布操作均需手动完成。")) {
                    EmptyView()
                }
            }
            .navigationTitle("内容排期")
            .navigationBarItems(trailing: Button(action: { showAddSheet = true }) {
                Image(systemName: "plus")
            })
            .sheet(isPresented: $showAddSheet) {
                ScheduleEditSheet(mode: .create, isPresented: $showAddSheet)
            }
            .sheet(isPresented: $showEditSheet) {
                if let item = editingItem {
                    ScheduleEditSheet(mode: .edit(item), isPresented: $showEditSheet)
                }
            }
            .onAppear {
                manager.requestNotificationPermission { _ in }
            }
        }
    }

    private func deleteItem(at offsets: IndexSet) {
        for index in offsets {
            manager.deleteItem(manager.items[index])
        }
    }
}

// MARK: - Schedule Row

struct ScheduleRowView: View {
    let item: ScheduleItem
    var isOverdue: Bool = false

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: item.platform.iconName)
                        .foregroundColor(.accentColor)
                        .font(.caption)
                    Text(item.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if isOverdue {
                        Text("逾期")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(4)
                    }
                }
                HStack {
                    Image(systemName: item.status.iconName)
                        .font(.caption2)
                    Text(item.status.displayName)
                        .font(.caption2)
                    Text(dateFormatter.string(from: item.plannedDate))
                        .font(.caption2)
                    if item.reminderEnabled {
                        Image(systemName: "bell.badge.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - Schedule Edit Sheet

enum ScheduleEditMode {
    case create
    case edit(ScheduleItem)
}

struct ScheduleEditSheet: View {
    @EnvironmentObject var manager: ContentSchedulerManager
    let mode: ScheduleEditMode
    @Binding var isPresented: Bool

    @State private var title = ""
    @State private var platform: ContentPlatform = .wechat
    @State private var plannedDate = Date().addingTimeInterval(86400)
    @State private var notes = ""
    @State private var status: ScheduleStatus = .planned
    @State private var reminderEnabled = true
    @State private var tagInput = ""
    @State private var tags: [String] = []

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("标题")) {
                    TextField("内容标题", text: $title)
                }

                Section(header: Text("平台")) {
                    Picker("发布平台", selection: $platform) {
                        ForEach(ContentPlatform.allCases, id: \.self) { p in
                            Label(p.displayName, systemImage: p.iconName).tag(p)
                        }
                    }
                }

                Section(header: Text("计划时间")) {
                    DatePicker("计划日期", selection: $plannedDate, displayedComponents: [.date, .hourAndMinute])
                }

                Section(header: Text("状态")) {
                    Picker("状态", selection: $status) {
                        ForEach(ScheduleStatus.allCases, id: \.self) { s in
                            Label(s.displayName, systemImage: s.iconName).tag(s)
                        }
                    }
                }

                Section(header: Text("提醒")) {
                    Toggle("启用提醒", isOn: $reminderEnabled)
                    if reminderEnabled {
                        Text("将在计划时间前 1 小时发送本地通知提醒")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("标签")) {
                    ForEach(tags.indices, id: \.self) { i in
                        Text("#\(tags[i])")
                    }
                    HStack {
                        TextField("添加标签", text: $tagInput)
                        Button("添加") {
                            if !tagInput.isEmpty {
                                tags.append(tagInput)
                                tagInput = ""
                            }
                        }
                    }
                }

                Section(header: Text("备注")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle(modeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("取消") { isPresented = false },
                trailing: Button("保存") { save() }
                    .disabled(title.isEmpty)
            )
            .onAppear {
                if case .edit(let item) = mode {
                    title = item.title
                    platform = item.platform
                    plannedDate = item.plannedDate
                    notes = item.notes
                    status = item.status
                    reminderEnabled = item.reminderEnabled
                    tags = item.tags
                }
            }
        }
    }

    private var modeTitle: String {
        switch mode {
        case .create: return "新建排期"
        case .edit: return "编辑排期"
        }
    }

    private func save() {
        switch mode {
        case .create:
            let item = ScheduleItem(
                title: title,
                platform: platform,
                plannedDate: plannedDate,
                notes: notes,
                tags: tags,
                reminderEnabled: reminderEnabled
            )
            manager.addItem(item)
        case .edit(let original):
            var updated = original
            updated.title = title
            updated.platform = platform
            updated.plannedDate = plannedDate
            updated.notes = notes
            updated.status = status
            updated.reminderEnabled = reminderEnabled
            updated.tags = tags
            manager.updateItem(updated)
        }
        isPresented = false
    }
}
