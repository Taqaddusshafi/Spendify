//
//  ContentView.swift
//  Spendify
//
//  Created by Taqaddus Shafi on 17/01/25.
//

import SwiftUI
import Charts

struct Expense: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var amount: Double
    var category: String
    var date: Date
}

struct ContentView: View {
    @State private var expenses = [Expense]()
    @State private var expenseName = ""
    @State private var expenseAmount = ""
    @State private var selectedCategory = "Food"
    @State private var selectedDate = Date()
    @State private var filterCategory = "All"
    @State private var showExportSheet = false

    let categories = ["Food", "Travel", "Shopping", "Bills", "Others"]
    
    func loadExpenses() {
        if let data = UserDefaults.standard.data(forKey: "expenses"),
           let decoded = try? JSONDecoder().decode([Expense].self, from: data) {
            expenses = decoded
        }
    }
    
    func saveExpenses() {
        if let encoded = try? JSONEncoder().encode(expenses) {
            UserDefaults.standard.set(encoded, forKey: "expenses")
        }
    }
    
    var filteredExpenses: [Expense] {
        expenses.filter { expense in
            filterCategory == "All" || expense.category == filterCategory
        }
    }
    
    var monthlySummary: [String: Double] {
        let currentMonth = Calendar.current.dateComponents([.year, .month], from: Date())
        let filtered = expenses.filter {
            let expenseMonth = Calendar.current.dateComponents([.year, .month], from: $0.date)
            return expenseMonth == currentMonth
        }
        
        return Dictionary(grouping: filtered, by: { $0.category })
            .mapValues { $0.reduce(0) { $0 + $1.amount } }
    }
    
    func exportExpenses() -> String {
        let csvHeader = "Name,Amount,Category,Date\n"
        let csvBody = expenses.map {
            "\($0.name),\($0.amount),\($0.category),\($0.date)"
        }.joined(separator: "\n")
        return csvHeader + csvBody
    }
    
    func deleteExpense(at offsets: IndexSet) {
        expenses.remove(atOffsets: offsets)
        saveExpenses()
    }

    var body: some View {
        NavigationView {
            VStack {
                // Monthly Summary Chart
                Chart(monthlySummary.sorted(by: { $0.key < $1.key }), id: \.key) { category, amount in
                    BarMark(
                        x: .value("Category", category),
                        y: .value("Amount", amount)
                    )
                    .foregroundStyle(by: .value("Category", category))
                }
                .padding()
                .frame(height: 200)
                
                // Filters
                Picker("Category", selection: $filterCategory) {
                    Text("All").tag("All")
                    ForEach(categories, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                // Scrollable List of Expenses
                List {
                    ForEach(filteredExpenses) { expense in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(expense.name)
                                    .font(.headline)
                                Text(expense.category)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Text("$\(expense.amount, specifier: "%.2f")")
                        }
                    }
                    .onDelete { indexSet in
                        deleteExpense(at: indexSet)
                    }
                }
                .listStyle(PlainListStyle()) // Ensures proper scrolling
                
                // Add Expense Form
                VStack {
                    HStack {
                        TextField("Expense Name", text: $expenseName)
                            .padding()
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        TextField("Amount", text: $expenseAmount)
                            .keyboardType(.decimalPad)
                            .padding()
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    .padding()
                    
                    HStack {
                        Picker("Category", selection: $selectedCategory) {
                            ForEach(categories, id: \.self) { category in
                                Text(category)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        
                        DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                    .padding()
                    
                    // Add Button
                    Button("Add Expense") {
                        if let amount = Double(expenseAmount), !expenseName.isEmpty {
                            let newExpense = Expense(name: expenseName, amount: amount, category: selectedCategory, date: selectedDate)
                            expenses.append(newExpense)
                            saveExpenses()
                            expenseName = ""
                            expenseAmount = ""
                        }
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .padding()
            }
            .navigationTitle("Expense Tracker")
            .onAppear {
                loadExpenses()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Export") {
                        showExportSheet.toggle()
                    }
                }
            }
            .sheet(isPresented: $showExportSheet) {
                ShareSheet(activityItems: [exportExpenses()])
            }
        }
    }
}

// Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
