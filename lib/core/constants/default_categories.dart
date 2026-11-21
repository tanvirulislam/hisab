/// Default category tree from PRD §7.1 plus income categories (§6.3).
///
/// Single source of truth for seeding and for the translated names of
/// system categories (`categories.system_key`). Never change or reuse an
/// existing [DefaultCategory.key]: stored data refers to it.
library;

class DefaultCategory {
  const DefaultCategory({
    required this.key,
    required this.en,
    required this.bn,
    required this.icon,
    this.color,
    this.isIncome = false,
    this.children = const [],
  });

  final String key;
  final String en;
  final String bn;
  final String icon;

  /// ARGB. Subcategories inherit their parent's color when null.
  final int? color;
  final bool isIncome;
  final List<DefaultCategory> children;
}

abstract final class SystemCategoryKeys {
  /// Fallback for uncategorized expenses. Cannot be deleted.
  static const String otherExpense = 'others';

  /// Fallback for uncategorized income. Cannot be deleted.
  static const String otherIncome = 'income.other';

  static const Set<String> protectedKeys = {otherExpense, otherIncome};
}

const List<DefaultCategory> defaultExpenseCategories = [
  DefaultCategory(
    key: 'grocery',
    en: 'Grocery & Bazar',
    bn: 'বাজার ও মুদি',
    icon: 'shopping_basket',
    color: 0xFF2E7D32,
    children: [
      DefaultCategory(key: 'grocery.rice', en: 'Rice', bn: 'চাল', icon: 'rice_bowl'),
      DefaultCategory(key: 'grocery.fish', en: 'Fish', bn: 'মাছ', icon: 'set_meal'),
      DefaultCategory(key: 'grocery.meat', en: 'Meat', bn: 'মাংস', icon: 'kebab_dining'),
      DefaultCategory(key: 'grocery.chicken', en: 'Chicken', bn: 'মুরগি', icon: 'kebab_dining'),
      DefaultCategory(key: 'grocery.vegetables', en: 'Vegetables', bn: 'সবজি', icon: 'eco'),
      DefaultCategory(key: 'grocery.fruits', en: 'Fruits', bn: 'ফল', icon: 'apple'),
      DefaultCategory(key: 'grocery.oil', en: 'Oil', bn: 'তেল', icon: 'oil_barrel'),
      DefaultCategory(key: 'grocery.milk', en: 'Milk', bn: 'দুধ', icon: 'local_drink'),
      DefaultCategory(key: 'grocery.eggs', en: 'Eggs', bn: 'ডিম', icon: 'egg'),
      DefaultCategory(key: 'grocery.spices', en: 'Spices', bn: 'মসলা', icon: 'grass'),
      DefaultCategory(key: 'grocery.other', en: 'Other Grocery', bn: 'অন্যান্য বাজার', icon: 'shopping_basket'),
    ],
  ),
  DefaultCategory(
    key: 'food',
    en: 'Food & Dining',
    bn: 'খাবার-দাবার',
    icon: 'restaurant',
    color: 0xFFE65100,
    children: [
      DefaultCategory(key: 'food.breakfast', en: 'Breakfast', bn: 'সকালের নাস্তা', icon: 'free_breakfast'),
      DefaultCategory(key: 'food.lunch', en: 'Lunch', bn: 'দুপুরের খাবার', icon: 'lunch_dining'),
      DefaultCategory(key: 'food.dinner', en: 'Dinner', bn: 'রাতের খাবার', icon: 'dinner_dining'),
      DefaultCategory(key: 'food.snacks', en: 'Snacks', bn: 'হালকা নাস্তা', icon: 'fastfood'),
      DefaultCategory(key: 'food.restaurant', en: 'Restaurant', bn: 'রেস্তোরাঁ', icon: 'restaurant'),
      DefaultCategory(key: 'food.tea_coffee', en: 'Tea/Coffee', bn: 'চা/কফি', icon: 'coffee'),
      DefaultCategory(key: 'food.outside', en: 'Outside Food', bn: 'বাইরের খাবার', icon: 'takeout_dining'),
    ],
  ),
  DefaultCategory(
    key: 'transport',
    en: 'Transportation',
    bn: 'যাতায়াত',
    icon: 'directions_bus',
    color: 0xFF1565C0,
    children: [
      DefaultCategory(key: 'transport.office', en: 'Office Transport', bn: 'অফিস যাতায়াত', icon: 'work'),
      DefaultCategory(key: 'transport.bus', en: 'Bus', bn: 'বাস', icon: 'directions_bus'),
      DefaultCategory(key: 'transport.rickshaw', en: 'Rickshaw', bn: 'রিকশা', icon: 'pedal_bike'),
      DefaultCategory(key: 'transport.cng', en: 'CNG', bn: 'সিএনজি', icon: 'electric_rickshaw'),
      DefaultCategory(key: 'transport.ride_share', en: 'Uber/Pathao', bn: 'উবার/পাঠাও', icon: 'local_taxi'),
      DefaultCategory(key: 'transport.other', en: 'Other Transport', bn: 'অন্যান্য যাতায়াত', icon: 'commute'),
    ],
  ),
  DefaultCategory(
    key: 'health',
    en: 'Medicine & Healthcare',
    bn: 'ওষুধ ও চিকিৎসা',
    icon: 'medical_services',
    color: 0xFFC62828,
    children: [
      DefaultCategory(key: 'health.medicine', en: 'Medicine', bn: 'ওষুধ', icon: 'medication'),
      DefaultCategory(key: 'health.doctor', en: 'Doctor Consultation', bn: 'ডাক্তার দেখানো', icon: 'medical_services'),
      DefaultCategory(key: 'health.tests', en: 'Medical Tests', bn: 'মেডিকেল টেস্ট', icon: 'biotech'),
      DefaultCategory(key: 'health.hospital', en: 'Hospital', bn: 'হাসপাতাল', icon: 'local_hospital'),
      DefaultCategory(key: 'health.other', en: 'Other Healthcare', bn: 'অন্যান্য চিকিৎসা', icon: 'health_and_safety'),
    ],
  ),
  DefaultCategory(
    key: 'utilities',
    en: 'Utilities',
    bn: 'ইউটিলিটি',
    icon: 'bolt',
    color: 0xFF00838F,
    children: [
      DefaultCategory(key: 'utilities.drinking_water', en: 'Drinking Water', bn: 'খাবার পানি', icon: 'water_drop'),
      DefaultCategory(key: 'utilities.water_jar', en: 'Water Jar', bn: 'পানির জার', icon: 'water'),
      DefaultCategory(key: 'utilities.electricity', en: 'Electricity', bn: 'বিদ্যুৎ', icon: 'bolt'),
      DefaultCategory(key: 'utilities.gas', en: 'Gas', bn: 'গ্যাস', icon: 'propane_tank'),
      DefaultCategory(key: 'utilities.internet', en: 'Internet', bn: 'ইন্টারনেট', icon: 'wifi'),
      DefaultCategory(key: 'utilities.mobile_recharge', en: 'Mobile Recharge', bn: 'মোবাইল রিচার্জ', icon: 'phone_android'),
      DefaultCategory(key: 'utilities.other', en: 'Other Utilities', bn: 'অন্যান্য ইউটিলিটি', icon: 'receipt_long'),
    ],
  ),
  DefaultCategory(
    key: 'household',
    en: 'Household',
    bn: 'গৃহস্থালি',
    icon: 'home',
    color: 0xFF6D4C41,
    children: [
      DefaultCategory(key: 'household.cleaning', en: 'Cleaning Supplies', bn: 'পরিষ্কারের সামগ্রী', icon: 'cleaning_services'),
      DefaultCategory(key: 'household.kitchen', en: 'Kitchen Supplies', bn: 'রান্নাঘরের সামগ্রী', icon: 'kitchen'),
      DefaultCategory(key: 'household.items', en: 'Household Items', bn: 'গৃহস্থালি জিনিস', icon: 'chair'),
      DefaultCategory(key: 'household.repairs', en: 'Repairs', bn: 'মেরামত', icon: 'handyman'),
      DefaultCategory(key: 'household.other', en: 'Other Household', bn: 'অন্যান্য গৃহস্থালি', icon: 'home'),
    ],
  ),
  DefaultCategory(
    key: 'shopping',
    en: 'Shopping & Personal Care',
    bn: 'কেনাকাটা ও ব্যক্তিগত যত্ন',
    icon: 'shopping_bag',
    color: 0xFFAD1457,
    children: [
      DefaultCategory(key: 'shopping.clothing', en: 'Clothing', bn: 'পোশাক', icon: 'checkroom'),
      DefaultCategory(key: 'shopping.shoes', en: 'Shoes', bn: 'জুতা', icon: 'directions_walk'),
      DefaultCategory(key: 'shopping.personal_care', en: 'Personal Care', bn: 'ব্যক্তিগত যত্ন', icon: 'spa'),
      DefaultCategory(key: 'shopping.accessories', en: 'Accessories', bn: 'অ্যাক্সেসরিজ', icon: 'watch'),
      DefaultCategory(key: 'shopping.other', en: 'Other Shopping', bn: 'অন্যান্য কেনাকাটা', icon: 'shopping_bag'),
    ],
  ),
  DefaultCategory(
    key: 'family',
    en: 'Family',
    bn: 'পরিবার',
    icon: 'family_restroom',
    color: 0xFF6A1B9A,
    children: [
      DefaultCategory(key: 'family.wife', en: 'Wife-related Expenses', bn: 'স্ত্রীর খরচ', icon: 'favorite'),
      DefaultCategory(key: 'family.purchases', en: 'Family Purchases', bn: 'পরিবারের কেনাকাটা', icon: 'shopping_cart'),
      DefaultCategory(key: 'family.activities', en: 'Family Activities', bn: 'পারিবারিক কার্যক্রম', icon: 'celebration'),
      DefaultCategory(key: 'family.other', en: 'Other Family Expenses', bn: 'অন্যান্য পারিবারিক খরচ', icon: 'family_restroom'),
    ],
  ),
  DefaultCategory(key: 'entertainment', en: 'Entertainment', bn: 'বিনোদন', icon: 'movie', color: 0xFFF9A825),
  DefaultCategory(key: 'education', en: 'Education', bn: 'শিক্ষা', icon: 'school', color: 0xFF283593),
  DefaultCategory(key: 'rent_bills', en: 'Rent & Bills', bn: 'ভাড়া ও বিল', icon: 'house', color: 0xFF4E342E),
  DefaultCategory(key: 'mobile_internet', en: 'Mobile & Internet', bn: 'মোবাইল ও ইন্টারনেট', icon: 'smartphone', color: 0xFF0277BD),
  DefaultCategory(key: 'gifts', en: 'Gifts', bn: 'উপহার', icon: 'card_giftcard', color: 0xFFD81B60),
  DefaultCategory(key: SystemCategoryKeys.otherExpense, en: 'Others', bn: 'অন্যান্য', icon: 'more_horiz', color: 0xFF546E7A),
];

const List<DefaultCategory> defaultIncomeCategories = [
  DefaultCategory(key: 'income.salary', en: 'Salary', bn: 'বেতন', icon: 'payments', color: 0xFF2E7D32, isIncome: true),
  DefaultCategory(key: 'income.bonus', en: 'Bonus', bn: 'বোনাস', icon: 'emoji_events', color: 0xFF558B2F, isIncome: true),
  DefaultCategory(key: 'income.freelance', en: 'Freelance Income', bn: 'ফ্রিল্যান্স আয়', icon: 'laptop', color: 0xFF00695C, isIncome: true),
  DefaultCategory(key: 'income.business', en: 'Business Income', bn: 'ব্যবসায়িক আয়', icon: 'storefront', color: 0xFF1565C0, isIncome: true),
  DefaultCategory(key: SystemCategoryKeys.otherIncome, en: 'Other Income', bn: 'অন্যান্য আয়', icon: 'attach_money', color: 0xFF546E7A, isIncome: true),
];

/// Flat lookup by key, built once.
final Map<String, DefaultCategory> defaultCategoryByKey = {
  for (final top in [...defaultExpenseCategories, ...defaultIncomeCategories]) ...{
    top.key: top,
    for (final child in top.children) child.key: child,
  },
};
