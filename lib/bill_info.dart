import 'package:flutter/material.dart';

/// How a class label from the model is shown to the user.
class BillInfo {
  const BillInfo({
    required this.name,
    required this.symbol,
    required this.color,
  });

  final String name;
  final String symbol;
  final Color color;
}

/// Keys must match the class names used when training the model
/// (the lines of labels.txt).
///
/// To support another bill: add a line here, photograph and label it with
/// the same name, and retrain (see README.md, "Changing the bills").
const Map<String, BillInfo> kBills = {
  // ---- Philippine peso
  'php_100': BillInfo(
    name: 'One Hundred Pesos',
    symbol: '\u20B1100',
    color: Color(0xFF7E57C2), // violet
  ),
  'php_500': BillInfo(
    name: 'Five Hundred Pesos',
    symbol: '\u20B1500',
    color: Color(0xFFFFC107), // yellow
  ),
  'php_1000': BillInfo(
    name: 'One Thousand Pesos',
    symbol: '\u20B11000',
    color: Color(0xFF1E88E5), // blue
  ),

  // ---- US dollar
  'usd_1': BillInfo(
    name: 'One US Dollar',
    symbol: '\$1',
    color: Color(0xFF43A047), // green
  ),
  'usd_5': BillInfo(
    name: 'Five US Dollars',
    symbol: '\$5',
    color: Color(0xFFAB47BC), // purple
  ),
  'usd_20': BillInfo(
    name: 'Twenty US Dollars',
    symbol: '\$20',
    color: Color(0xFF2E7D32), // dark green
  ),

  // ---- Euro
  'eur_5': BillInfo(
    name: 'Five Euros',
    symbol: '\u20AC5',
    color: Color(0xFF9E9E9E), // grey
  ),
  'eur_10': BillInfo(
    name: 'Ten Euros',
    symbol: '\u20AC10',
    color: Color(0xFFE53935), // red
  ),
  'eur_20': BillInfo(
    name: 'Twenty Euros',
    symbol: '\u20AC20',
    color: Color(0xFF039BE5), // light blue
  ),
};

/// Falls back to the raw label if the class is not in [kBills].
BillInfo billInfoFor(String label) =>
    kBills[label] ??
    BillInfo(name: label, symbol: label, color: const Color(0xFF607D8B));
