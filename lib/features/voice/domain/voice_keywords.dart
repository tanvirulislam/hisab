/// Spoken words that point to a seeded category, keyed by `system_key`.
///
/// A leading `~` marks a weak, context word (বাজার, অফিস): it is used only
/// when no specific word matches, so "বাজারে মাছ" is Fish, not just Grocery.
/// Multi-word entries are phrases ("রাতের খাবার"). Words may carry Bangla
/// case endings when spoken (বাজারে, রিকশায়); matching handles that.
///
/// User-created and renamed categories are matched by their names, so this
/// list only needs the seeded tree.
library;

const Map<String, List<String>> voiceKeywords = {
  // ------------------------------------------------------------- expense
  'grocery': ['~বাজার', '~মুদি', '~grocery', '~groceries', '~bazar', '~bazaar', '~market'],
  'grocery.rice': ['চাল', 'চাউল', 'rice'],
  'grocery.fish': ['মাছ', 'ইলিশ', 'রুই', 'পাঙ্গাস', 'চিংড়ি', 'fish', 'hilsa', 'prawn', 'shrimp'],
  'grocery.meat': ['মাংস', 'গোশত', 'গরুর মাংস', 'খাসির মাংস', 'meat', 'beef', 'mutton'],
  'grocery.chicken': ['মুরগি', 'মুরগী', 'চিকেন', 'chicken'],
  'grocery.vegetables': [
    'সবজি', 'সবজী', 'তরকারি', 'শাক', 'আলু', 'পেঁয়াজ', 'টমেটো', 'বেগুন',
    'vegetable', 'vegetables', 'veg', 'potato', 'potatoes', 'onion', 'onions', 'tomato', 'tomatoes',
  ],
  'grocery.fruits': ['ফল', 'ফলমূল', 'আম', 'কলা', 'আপেল', 'কমলা', 'fruit', 'fruits', 'mango', 'banana', 'apple'],
  'grocery.oil': ['তেল', 'সয়াবিন', 'oil'],
  'grocery.milk': ['দুধ', 'milk'],
  'grocery.eggs': ['ডিম', 'egg', 'eggs'],
  'grocery.spices': ['মসলা', 'মশলা', 'লবণ', 'হলুদ', 'মরিচ', 'spice', 'spices', 'salt'],
  'grocery.other': ['ডাল', 'চিনি', 'আটা', 'ময়দা', 'lentil', 'lentils', 'dal', 'sugar', 'flour'],

  'food': ['~খাবার', '~food', '~meal'],
  'food.breakfast': ['সকালের নাস্তা', 'ব্রেকফাস্ট', 'breakfast'],
  'food.lunch': ['দুপুরের খাবার', 'লাঞ্চ', 'lunch'],
  'food.dinner': ['রাতের খাবার', 'ডিনার', 'dinner'],
  'food.snacks': ['নাস্তা', 'স্ন্যাকস', 'সিঙ্গারা', 'শিঙ্গারা', 'পুরি', 'চিপস', 'বিস্কুট', 'snack', 'snacks', 'biscuit'],
  'food.restaurant': ['রেস্টুরেন্ট', 'রেস্তোরাঁ', 'হোটেল', 'restaurant', 'hotel'],
  'food.tea_coffee': ['চা', 'কফি', 'tea', 'coffee'],
  'food.outside': ['বাইরের খাবার', 'বাইরে খাওয়া', 'ফুডপান্ডা', 'foodpanda', 'outside food'],

  'transport': ['~যাতায়াত', '~transport', '~travel', '~fare'],
  'transport.office': [
    'অফিস যাওয়া', 'অফিসে যাওয়া', 'অফিস যাতায়াত', 'office transport', 'office commute',
    '~অফিস', '~office',
  ],
  'transport.bus': ['বাস', 'বাসভাড়া', 'bus'],
  'transport.rickshaw': ['রিকশা', 'রিক্সা', 'rickshaw'],
  'transport.cng': ['সিএনজি', 'অটো', 'cng', 'auto'],
  'transport.ride_share': ['উবার', 'পাঠাও', 'uber', 'pathao', 'ride share'],
  'transport.other': ['ট্রেন', 'লঞ্চ', 'ট্যাক্সি', 'পেট্রোল', 'অকটেন', 'train', 'launch', 'taxi', 'petrol', 'fuel'],

  'health': ['~চিকিৎসা', '~health', '~treatment'],
  'health.medicine': ['ওষুধ', 'ঔষধ', 'ট্যাবলেট', 'medicine', 'medicines', 'tablet', 'tablets', 'pharmacy'],
  'health.doctor': ['ডাক্তার', 'ডাক্তার দেখানো', 'ভিজিট', 'doctor', 'consultation'],
  'health.tests': ['মেডিকেল টেস্ট', 'রক্ত পরীক্ষা', 'blood test', 'medical test', '~টেস্ট', '~test'],
  'health.hospital': ['হাসপাতাল', 'ক্লিনিক', 'hospital', 'clinic'],

  'utilities': ['~ইউটিলিটি', '~utility', '~utilities'],
  'utilities.drinking_water': ['খাবার পানি', 'পানি', 'drinking water', 'water'],
  'utilities.water_jar': ['পানির জার', 'জার', 'water jar'],
  'utilities.electricity': ['বিদ্যুৎ', 'কারেন্ট', 'বিদ্যুৎ বিল', 'কারেন্ট বিল', 'electricity', 'electric bill'],
  'utilities.gas': ['গ্যাস', 'গ্যাস বিল', 'সিলিন্ডার', 'gas', 'cylinder'],
  'utilities.internet': ['ইন্টারনেট', 'ওয়াইফাই', 'ব্রডব্যান্ড', 'internet', 'wifi', 'broadband'],
  'utilities.mobile_recharge': ['রিচার্জ', 'ফ্লেক্সিলোড', 'মোবাইল রিচার্জ', 'recharge', 'flexiload', 'top up'],

  'household': ['~গৃহস্থালি', '~সংসার', '~household'],
  'household.cleaning': ['সাবান', 'ডিটারজেন্ট', 'হারপিক', 'ঝাড়ু', 'soap', 'detergent', 'cleaning'],
  'household.kitchen': ['হাঁড়ি', 'পাতিল', 'রান্নাঘর', 'kitchen'],
  'household.items': ['আসবাব', 'ফার্নিচার', 'বালতি', 'furniture', 'bucket'],
  'household.repairs': ['মেরামত', 'মিস্ত্রি', 'repair', 'repairs', 'plumber', 'electrician'],

  'shopping': ['~শপিং', '~কেনাকাটা', '~shopping'],
  'shopping.clothing': [
    'জামা', 'কাপড়', 'শার্ট', 'প্যান্ট', 'শাড়ি', 'লুঙ্গি', 'পাঞ্জাবি',
    'clothes', 'clothing', 'shirt', 'pant', 'pants', 'dress',
  ],
  'shopping.shoes': ['জুতা', 'স্যান্ডেল', 'shoe', 'shoes', 'sandal', 'sandals'],
  'shopping.personal_care': ['শ্যাম্পু', 'ক্রিম', 'পারফিউম', 'সেলুন', 'চুল কাটা', 'shampoo', 'salon', 'haircut', 'cosmetics'],
  'shopping.accessories': ['ঘড়ি', 'ব্যাগ', 'watch', 'bag', 'accessories'],

  'family': ['~পরিবার', '~family'],
  'family.wife': ['বউ', 'স্ত্রী', 'wife'],
  'family.activities': ['বেড়ানো', 'পিকনিক', 'picnic', 'outing'],

  'entertainment': ['সিনেমা', 'মুভি', 'নেটফ্লিক্স', 'বিনোদন', 'movie', 'cinema', 'netflix', 'game'],
  'education': ['বই', 'খাতা', 'কলম', 'স্কুল', 'কলেজ', 'টিউশন', 'কোচিং', 'book', 'books', 'school', 'tuition', 'coaching'],
  'rent_bills': ['বাসা ভাড়া', 'বাড়ি ভাড়া', 'house rent', 'rent', '~ভাড়া', '~বিল', '~bill'],
  'mobile_internet': ['মোবাইল বিল', 'phone bill', 'mobile bill'],
  'gifts': ['উপহার', 'গিফট', 'gift', 'gifts'],

  // -------------------------------------------------------------- income
  'income.salary': ['বেতন', 'স্যালারি', 'মাইনে', 'salary'],
  'income.bonus': ['বোনাস', 'bonus'],
  'income.freelance': ['ফ্রিল্যান্স', 'ফ্রিল্যান্সিং', 'freelance', 'freelancing', 'upwork', 'fiverr'],
  'income.business': ['ব্যবসা', 'বিক্রি', 'লাভ', 'business', 'sales', 'profit'],
};

/// Words that make a sentence income (§6.3) unless an expense verb is also
/// present ("স্কুলের বেতন দিয়েছি" is a paid fee, not a salary).
const List<String> incomeCues = [
  'বেতন', 'স্যালারি', 'মাইনে', 'বোনাস', 'আয়', 'পেয়েছি', 'পেলাম', 'পাইছি', 'পেয়েছে',
  'salary', 'bonus', 'income', 'received', 'earned', 'got paid', 'freelance', 'business',
];

const List<String> expenseVerbs = [
  'দিয়েছি', 'দিলাম', 'দিছি', 'খরচ', 'কিনেছি', 'কিনলাম', 'কিনছি', 'কেনা', 'পরিশোধ', 'বাবদ',
  'paid', 'pay', 'spent', 'spend', 'bought', 'buy', 'purchased', 'cost',
];

/// A refund is recorded from the original expense (D5), never as income.
const List<String> refundCues = ['ফেরত', 'রিফান্ড', 'refund', 'refunded', 'returned'];

const List<String> currencyWords = ['টাকা', 'taka', 'tk', 'bdt', 'rs', 'rupees', '৳'];

/// Words after a number that make it a quantity, not an amount.
const List<String> quantityUnits = [
  'কেজি', 'গ্রাম', 'লিটার', 'টা', 'টি', 'পিস', 'কাপ', 'প্যাকেট', 'ডজন', 'হালি', 'জন', 'বার',
  'ঘণ্টা', 'মিনিট', 'মাস', 'বছর', 'kg', 'kgs', 'gram', 'grams', 'g', 'litre', 'liter', 'litres',
  'piece', 'pieces', 'pcs', 'cup', 'cups', 'packet', 'packets', 'dozen', 'people', 'times',
  'hours', 'hour', 'minutes', 'months', 'month', 'years', 'year',
];

/// Words that split one sentence into several items.
const List<String> itemSeparators = ['আর', 'এবং', 'ও', 'and', 'plus', 'then', 'তারপর', 'also'];

/// Filler left out of the generated description.
const List<String> fillerWords = [
  'আমি', 'আমার', 'আমরা', 'কিনেছি', 'কিনলাম', 'কিনছি', 'কিনে', 'কেনা', 'খরচ', 'হয়েছে', 'হয়েছিল', 'হলো',
  'হল', 'করেছি', 'করলাম', 'করে', 'দিয়েছি', 'দিলাম', 'দিছি', 'দিয়ে', 'বাবদ', 'জন্য', 'খেয়েছি', 'খেলাম',
  'পেয়েছি', 'পেলাম', 'পাইছি', 'গেছে', 'লেগেছে', 'লাগলো', 'লাগছে', 'মোট', 'প্রায়', 'দাম', 'পরিশোধ',
  'i', 'we', 'my', 'spent', 'spend', 'paid', 'pay', 'bought', 'buy', 'for', 'on', 'the', 'a', 'an',
  'of', 'got', 'received', 'was', 'is', 'cost', 'costs', 'total', 'about', 'some',
];
