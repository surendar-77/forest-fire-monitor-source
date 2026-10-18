import 'package:flutter/material.dart';

String getRiskLevel(int score) {
  if (score <= 30) {
    return 'LOW';
  } else if (score <= 60) {
    return 'MODERATE';
  } else if (score <= 80) {
    return 'HIGH';
  } else {
    return 'CRITICAL';
  }
}

Color riskColor(String riskLevel) {
  switch (riskLevel) {
    case 'LOW':
      return Colors.green;
    case 'MODERATE':
      return Colors.orange;
    case 'HIGH':
      return Colors.deepOrange;
    case 'CRITICAL':
      return Colors.red;
    default:
      return Colors.grey;
  }
}
