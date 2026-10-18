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
