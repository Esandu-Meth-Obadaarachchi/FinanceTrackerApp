import 'package:flutter/material.dart';

/// A selectable income/expense category.
class CategoryDef {
  final String id;
  final String label;
  final String note; // income: descriptive note
  final bool taxable; // income: assessable for tax
  final bool deductible; // expense: tax-deductible
  final String group; // expense grouping (Fixed/Personal/Business/Other)

  const CategoryDef({
    required this.id,
    required this.label,
    this.note = '',
    this.taxable = false,
    this.deductible = false,
    this.group = '',
  });
}

/// Income categories — Sri Lanka AITC aligned.
const List<CategoryDef> kIncomeCategories = [
  CategoryDef(id: 'employment', label: 'Employment Income', taxable: true, note: 'Salary, wages, bonus, allowances'),
  CategoryDef(id: 'freelance', label: 'Freelance / Contract', taxable: true, note: 'Project fees, consulting'),
  CategoryDef(id: 'business', label: 'Business / Trade Income', taxable: true, note: 'Revenue from business operations'),
  CategoryDef(id: 'rental', label: 'Rental Income', taxable: true, note: 'Property or asset rental'),
  CategoryDef(id: 'interest', label: 'Interest Income', taxable: true, note: 'Bank interest, FD returns'),
  CategoryDef(id: 'dividends', label: 'Dividends / Investment', taxable: true, note: 'Share dividends, investment returns'),
  CategoryDef(id: 'capital_gain', label: 'Capital Gains', taxable: true, note: 'Property or asset sale profit'),
  CategoryDef(id: 'scholarship', label: 'Scholarship / Bursary', taxable: false, note: 'Generally exempt from tax'),
  CategoryDef(id: 'reimbursement', label: 'Reimbursement', taxable: false, note: 'Expense reimbursements'),
  CategoryDef(id: 'loan_in', label: 'Loan Received', taxable: false, note: 'Not assessable income'),
  CategoryDef(id: 'gift', label: 'Gift / Inheritance', taxable: false, note: 'May be exempt — consult advisor'),
  CategoryDef(id: 'other_income', label: 'Other Assessable Income', taxable: true, note: 'Any other taxable source'),
];

/// Expense categories, grouped.
const List<CategoryDef> kExpenseCategories = [
  CategoryDef(id: 'loan_repay', label: 'Loan Repayment', group: 'Fixed', deductible: true),
  CategoryDef(id: 'rent', label: 'Rent / Housing', group: 'Fixed'),
  CategoryDef(id: 'utilities', label: 'Utilities & Bills', group: 'Fixed'),
  CategoryDef(id: 'insurance', label: 'Insurance Premiums', group: 'Fixed', deductible: true),
  CategoryDef(id: 'vehicle', label: 'Vehicle / Transport', group: 'Fixed'),
  CategoryDef(id: 'food', label: 'Food & Groceries', group: 'Personal'),
  CategoryDef(id: 'fuel', label: 'Fuel', group: 'Personal'),
  CategoryDef(id: 'health', label: 'Healthcare / Medical', group: 'Personal', deductible: true),
  CategoryDef(id: 'pharmacy', label: 'Pharmacy & Medicine', group: 'Personal', deductible: true),
  CategoryDef(id: 'education', label: 'Education & Training', group: 'Personal', deductible: true),
  CategoryDef(id: 'shopping', label: 'Shopping & Clothing', group: 'Personal'),
  CategoryDef(id: 'entertainment', label: 'Entertainment & Dining', group: 'Personal'),
  CategoryDef(id: 'pet', label: 'Pet Care', group: 'Personal'),
  CategoryDef(id: 'subscriptions', label: 'Software & Subscriptions', group: 'Business', deductible: true),
  CategoryDef(id: 'marketing', label: 'Marketing & Advertising', group: 'Business', deductible: true),
  CategoryDef(id: 'office', label: 'Office & Stationery', group: 'Business', deductible: true),
  CategoryDef(id: 'biz_travel', label: 'Business Travel', group: 'Business', deductible: true),
  CategoryDef(id: 'prof_fees', label: 'Professional Fees', group: 'Business', deductible: true),
  CategoryDef(id: 'equipment', label: 'Equipment & Technology', group: 'Business', deductible: true),
  CategoryDef(id: 'family', label: 'Family Support', group: 'Other'),
  CategoryDef(id: 'donations', label: 'Gifts & Donations', group: 'Other', deductible: true),
  CategoryDef(id: 'savings', label: 'Savings / Investment', group: 'Other'),
  CategoryDef(id: 'other_exp', label: 'Other', group: 'Other'),
];

/// Per-category dot colours.
const Map<String, Color> kCategoryColors = {
  'Employment Income': Color(0xFF3DEBA8),
  'Freelance / Contract': Color(0xFF60A5FA),
  'Business / Trade Income': Color(0xFF34D399),
  'Rental Income': Color(0xFFA78BFA),
  'Interest Income': Color(0xFFF472B6),
  'Dividends / Investment': Color(0xFFFBBF24),
  'Capital Gains': Color(0xFFFB923C),
  'Scholarship / Bursary': Color(0xFF94A3B8),
  'Reimbursement': Color(0xFFCBD5E1),
  'Loan Received': Color(0xFFFB923C),
  'Gift / Inheritance': Color(0xFFE879F9),
  'Other Assessable Income': Color(0xFF94A3B8),
  'Loan Repayment': Color(0xFFFB923C),
  'Rent / Housing': Color(0xFF6366F1),
  'Utilities & Bills': Color(0xFF14B8A6),
  'Insurance Premiums': Color(0xFF0EA5E9),
  'Vehicle / Transport': Color(0xFFEAB308),
  'Food & Groceries': Color(0xFFF97316),
  'Fuel': Color(0xFFEAB308),
  'Healthcare / Medical': Color(0xFFEC4899),
  'Pharmacy & Medicine': Color(0xFFF43F5E),
  'Education & Training': Color(0xFF8B5CF6),
  'Shopping & Clothing': Color(0xFFF43F5E),
  'Entertainment & Dining': Color(0xFF06B6D4),
  'Pet Care': Color(0xFF84CC16),
  'Software & Subscriptions': Color(0xFF6366F1),
  'Marketing & Advertising': Color(0xFF0EA5E9),
  'Office & Stationery': Color(0xFF94A3B8),
  'Business Travel': Color(0xFF60A5FA),
  'Professional Fees': Color(0xFFA78BFA),
  'Equipment & Technology': Color(0xFF34D399),
  'Family Support': Color(0xFF84CC16),
  'Gifts & Donations': Color(0xFFE879F9),
  'Savings / Investment': Color(0xFF3DEBA8),
  'Other': Color(0xFF94A3B8),
  'Transfer': Color(0xFF60A5FA),
};

Color categoryColor(String category) =>
    kCategoryColors[category] ?? const Color(0xFF94A3B8);

/// Whether an income category label is taxable/assessable.
bool isCategoryTaxable(String label) {
  for (final c in kIncomeCategories) {
    if (c.label == label) return c.taxable;
  }
  return false;
}

/// Whether an expense category label is tax-deductible.
bool isCategoryDeductible(String label) {
  for (final c in kExpenseCategories) {
    if (c.label == label) return c.deductible;
  }
  return false;
}

/// Selectable account accent colours.
const List<Color> kAccountColors = [
  Color(0xFF3DEBA8),
  Color(0xFF60A5FA),
  Color(0xFFFFB547),
  Color(0xFFA78BFA),
  Color(0xFFF472B6),
  Color(0xFF34D399),
  Color(0xFFFB923C),
  Color(0xFF06B6D4),
];
