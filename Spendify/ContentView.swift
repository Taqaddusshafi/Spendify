import SwiftUI
import Charts
import UserNotifications

// MARK: - UIApplication Extension for Keyboard Dismissal
extension UIApplication {
    func endEditing() {
        windows.first?.endEditing(true)
    }
}

// MARK: - Expense Model
struct Expense: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var amount: Double
    var category: String
    var date: Date
}

// MARK: - ContentView
struct ContentView: View {
    @State private var expenses = [Expense]()
    @State private var expenseName = ""
    @State private var expenseAmount = ""
    @State private var selectedCategory = "Food"
    @State private var selectedDate = Date()
    @State private var filterCategory = "All"
    @State private var showExportSheet = false
    @State private var searchText = ""
    @State private var budgets: [String: Double] = [:]
    @State private var editExpense: Expense? = nil
    @State private var selectedCurrency = "USD"
    @State private var showBudgetSheet = false
    
    let categories = ["Food", "Travel", "Shopping", "Bills", "Others"]
    let currencies = ["USD", "EUR", "GBP", "JPY", "INR", "AUD"]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack {
                    currencyPicker
                    totalSpendingView
                    monthlyChart
                    budgetSection
                    filtersSection
                    expensesList
                    addExpenseForm
                }
                .onTapGesture {
                    // Dismiss the keyboard when tapping outside the text fields
                    UIApplication.shared.endEditing()
                }
            }
            .navigationTitle("Expense Tracker")
            .onAppear(perform: loadData)
            .toolbar { exportButton }
            .sheet(isPresented: $showBudgetSheet) { budgetView }
            .sheet(item: $editExpense) { expense in editExpenseView(for: expense) }
            .sheet(isPresented: $showExportSheet) { ShareSheet(activityItems: [exportExpenses()]) }
        }
    }
    
    // MARK: - Subviews
    
    private var currencyPicker: some View {
        Picker("Currency", selection: $selectedCurrency) {
            ForEach(currencies, id: \.self) { Text($0) }
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding()
    }
    
    private var totalSpendingView: some View {
        Text("Total Spending: \(selectedCurrency) \(totalSpending, specifier: "%.2f")")
            .font(.title2)
            .padding()
    }
    
    private var monthlyChart: some View {
        Chart(monthlySummary.sorted(by: { $0.key < $1.key }), id: \.key) { category, amount in
            BarMark(x: .value("Category", category), y: .value("Amount", amount))
                .foregroundStyle(by: .value("Category", category))
        }
        .padding()
        .frame(height: 200)
    }
    
    private var budgetSection: some View {
        Group {
            ForEach(budgets.sorted(by: { $0.key < $1.key }), id: \.key) { category, budget in
                BudgetProgressView(
                    category: category,
                    spent: monthlySummary[category] ?? 0,
                    budget: budget,
                    currency: selectedCurrency
                )
            }
            
            Button("Set Budget") { showBudgetSheet.toggle() }
                .buttonStyle(GreenButtonStyle())
        }
    }
    
    private var filtersSection: some View {
        Group {
            Picker("Category", selection: $filterCategory) {
                Text("All").tag("All")
                ForEach(categories, id: \.self) { Text($0) }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            TextField("Search", text: $searchText)
                .padding()
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
    
    private var expensesList: some View {
        List {
            ForEach(filteredExpenses) { expense in
                ExpenseRow(
                    expense: expense,
                    currency: selectedCurrency,
                    onEdit: { editExpense = expense }
                )
            }
            .onDelete(perform: deleteExpense)
        }
        .listStyle(PlainListStyle())
        .frame(height: 300)
    }
    
    private var addExpenseForm: some View {
        VStack {
            HStack {
                TextField("Expense Name", text: $expenseName)
                TextField("Amount", text: $expenseAmount)
                    .keyboardType(.decimalPad)
            }
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .padding()
            
            HStack {
                Picker("Category", selection: $selectedCategory) {
                    ForEach(categories, id: \.self) { Text($0) }
                }
                DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                    .labelsHidden()
            }
            .padding()
            
            Button("Add Expense", action: addExpense)
                .buttonStyle(BlueButtonStyle())
        }
        .padding()
    }
    
    private var exportButton: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button("Export") { showExportSheet.toggle() }
        }
    }
    
    private var budgetView: some View {
        BudgetView(budgets: $budgets, categories: categories, currency: $selectedCurrency) {
            saveExpenses()
            showBudgetSheet = false
        }
    }
    
    private func editExpenseView(for expense: Expense) -> some View {
        EditExpenseView(expense: Binding(
            get: { expense },
            set: { newValue in
                if let index = expenses.firstIndex(where: { $0.id == newValue.id }) {
                    expenses[index] = newValue
                    saveExpenses()
                }
            }
        ), currency: $selectedCurrency) {
            editExpense = nil
        }
    }
    
    // MARK: - Data Management
    
    private var filteredExpenses: [Expense] {
        expenses.filter {
            (filterCategory == "All" || $0.category == filterCategory) &&
            (searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText))
        }
    }
    
    private var monthlySummary: [String: Double] {
        let currentMonth = Calendar.current.dateComponents([.year, .month], from: Date())
        return Dictionary(grouping: expenses.filter {
            Calendar.current.dateComponents([.year, .month], from: $0.date) == currentMonth
        }, by: \.category).mapValues { $0.reduce(0) { $0 + $1.amount } }
    }
    
    private var totalSpending: Double {
        expenses.reduce(0) { $0 + $1.amount }
    }
    
    private func loadData() {
        loadExpenses()
        requestNotificationPermission()
    }
    
    private func loadExpenses() {
        if let data = UserDefaults.standard.data(forKey: "expenses"),
           let decoded = try? JSONDecoder().decode([Expense].self, from: data) {
            expenses = decoded
        }
        if let budgetData = UserDefaults.standard.data(forKey: "budgets"),
           let decodedBudgets = try? JSONDecoder().decode([String: Double].self, from: budgetData) {
            budgets = decodedBudgets
        }
    }
    
    private func saveExpenses() {
        if let encoded = try? JSONEncoder().encode(expenses) {
            UserDefaults.standard.set(encoded, forKey: "expenses")
        }
        if let encodedBudgets = try? JSONEncoder().encode(budgets) {
            UserDefaults.standard.set(encodedBudgets, forKey: "budgets")
        }
    }
    
    private func addExpense() {
        guard let amount = Double(expenseAmount), !expenseName.isEmpty else { return }
        expenses.append(Expense(
            name: expenseName,
            amount: amount,
            category: selectedCategory,
            date: selectedDate
        ))
        saveExpenses()
        expenseName = ""
        expenseAmount = ""
        checkBudget()
    }
    
    private func deleteExpense(at offsets: IndexSet) {
        expenses.remove(atOffsets: offsets)
        saveExpenses()
    }
    
    private func checkBudget() {
        for (category, amount) in monthlySummary {
            if let budget = budgets[category], amount > budget {
                sendNotification(title: "Budget Exceeded", body: "\(category) budget exceeded!")
            }
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        ))
    }
    
    private func exportExpenses() -> String {
        "Name,Amount,Category,Date\n" + expenses.map {
            "\($0.name),\($0.amount),\($0.category),\($0.date)"
        }.joined(separator: "\n")
    }
}

// MARK: - Component Views

struct BudgetProgressView: View {
    let category: String
    let spent: Double
    let budget: Double
    let currency: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("\(category) Budget: \(currency)\(spent, specifier: "%.2f")/\(currency)\(budget, specifier: "%.2f")")
            ProgressView(value: spent, total: budget)
                .accentColor(spent > budget ? .red : .blue)
        }
        .padding()
    }
}

struct ExpenseRow: View {
    let expense: Expense
    let currency: String
    let onEdit: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(expense.name).font(.headline)
                Text(expense.category).font(.subheadline).foregroundColor(.gray)
            }
            Spacer()
            Text("\(currency)\(expense.amount, specifier: "%.2f")")
            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
        }
    }
}

struct BudgetView: View {
    @Binding var budgets: [String: Double]
    let categories: [String]
    @Binding var currency: String
    var onSave: () -> Void
    
    @State private var selectedCategory = "Food"
    @State private var budgetAmount = ""
    
    var body: some View {
        NavigationView {
            Form {
                Picker("Category", selection: $selectedCategory) {
                    ForEach(categories, id: \.self) { Text($0) }
                }
                TextField("Amount (\(currency))", text: $budgetAmount)
                    .keyboardType(.decimalPad)
            }
            .navigationTitle("Set Budget")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        if let amount = Double(budgetAmount) {
                            budgets[selectedCategory] = amount
                            onSave()
                        }
                    }
                }
            }
        }
    }
}

struct EditExpenseView: View {
    @Binding var expense: Expense
    @Binding var currency: String
    var onSave: () -> Void
    
    @State private var name: String
    @State private var amount: String
    @State private var category: String
    @State private var date: Date
    
    init(expense: Binding<Expense>, currency: Binding<String>, onSave: @escaping () -> Void) {
        self._expense = expense
        self._currency = currency
        self.onSave = onSave
        self._name = State(initialValue: expense.wrappedValue.name)
        self._amount = State(initialValue: String(expense.wrappedValue.amount))
        self._category = State(initialValue: expense.wrappedValue.category)
        self._date = State(initialValue: expense.wrappedValue.date)
    }
    
    var body: some View {
        NavigationView {
            Form {
                TextField("Name", text: $name)
                TextField("Amount (\(currency))", text: $amount)
                    .keyboardType(.decimalPad)
                Picker("Category", selection: $category) {
                    ForEach(["Food", "Travel", "Shopping", "Bills", "Others"], id: \.self) {
                        Text($0)
                    }
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }
            .navigationTitle("Edit Expense")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        if let amountValue = Double(amount), !name.isEmpty {
                            expense = Expense(
                                id: expense.id,
                                name: name,
                                amount: amountValue,
                                category: category,
                                date: date
                            )
                            onSave()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Button Styles

struct BlueButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
    }
}

struct GreenButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(10)
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
