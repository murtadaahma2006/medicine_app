abstract final class CalculatorsLogic {
  // ---------------------------------------------------------------------------
  // 1. Wells' Criteria for PE
  // ---------------------------------------------------------------------------
  static const Map<String, double> wellsPeCriteria = <String, double>{
    'Clinical signs and symptoms of DVT': 3.0,
    'PE is #1 diagnosis OR equally likely': 3.0,
    'Heart rate > 100': 1.5,
    'Immobilization at least 3 days OR surgery in the previous 4 weeks': 1.5,
    'Previous, objectively diagnosed PE or DVT': 1.5,
    'Hemoptysis': 1.0,
    'Malignancy with treatment within 6 months or palliative': 1.0,
  };

  static String interpretWellsPe(double score) {
    if (score > 6.0) return 'High Risk (High probability of PE)';
    if (score >= 2.0 && score <= 6.0) return 'Moderate Risk (Moderate probability of PE)';
    return 'Low Risk (Low probability of PE)';
  }

  static double calculateWellsPe(Map<String, bool> selections) {
    double score = 0.0;
    for (final MapEntry<String, bool> entry in selections.entries) {
      if (entry.value) {
        score += wellsPeCriteria[entry.key] ?? 0.0;
      }
    }
    return score;
  }

  // ---------------------------------------------------------------------------
  // 2. CHA2DS2-VASc Score for Atrial Fibrillation Stroke Risk
  // ---------------------------------------------------------------------------
  static const Map<String, int> cha2ds2VascCriteria = <String, int>{
    'Congestive heart failure': 1,
    'Hypertension': 1,
    'Age ≥ 75 years': 2,
    'Diabetes mellitus': 1,
    'Stroke/TIA/TE': 2,
    'Vascular disease (prior MI, PAD, or aortic plaque)': 1,
    'Age 65-74 years': 1,
    'Sex category (Female)': 1, // Usually female adds 1, male adds 0
  };

  static String interpretCha2ds2Vasc(int score) {
    if (score == 0) return 'Low Risk (Omit antithrombotic therapy)';
    if (score == 1) return 'Moderate Risk (Consider oral anticoagulant or aspirin)';
    return 'High Risk (Oral anticoagulant recommended)';
  }

  static int calculateCha2ds2Vasc(Map<String, bool> selections) {
    int score = 0;
    // Cannot have both Age >= 75 and Age 65-74 selected, UI should handle this
    for (final MapEntry<String, bool> entry in selections.entries) {
      if (entry.value) {
        score += cha2ds2VascCriteria[entry.key] ?? 0;
      }
    }
    return score;
  }

  // ---------------------------------------------------------------------------
  // 3. Creatinine Clearance (Cockcroft-Gault)
  // ---------------------------------------------------------------------------
  static double calculateCrCl({
    required double age, // years
    required double weight, // kg
    required double serumCr, // mg/dL
    required bool isFemale,
  }) {
    if (serumCr <= 0) return 0.0;
    double crCl = ((140.0 - age) * weight) / (72.0 * serumCr);
    if (isFemale) {
      crCl *= 0.85;
    }
    return crCl; // mL/min
  }

  static String interpretCrCl(double crCl) {
    if (crCl >= 90) return 'Normal (Stage 1 CKD if kidney damage present)';
    if (crCl >= 60) return 'Mildly Decreased (Stage 2 CKD)';
    if (crCl >= 30) return 'Mild to Severely Decreased (Stage 3 CKD)';
    if (crCl >= 15) return 'Severely Decreased (Stage 4 CKD)';
    return 'Kidney Failure (Stage 5 CKD)';
  }

  // ---------------------------------------------------------------------------
  // 4. Child-Pugh Score for Cirrhosis Mortality
  // ---------------------------------------------------------------------------
  static int getChildPughPointsEncephalopathy(String grade) {
    switch (grade) {
      case 'None':
        return 1;
      case 'Grade 1-2':
        return 2;
      case 'Grade 3-4':
        return 3;
      default:
        return 1;
    }
  }

  static int getChildPughPointsAscites(String ascites) {
    switch (ascites) {
      case 'None':
        return 1;
      case 'Mild/Moderate (Diuretic-responsive)':
        return 2;
      case 'Severe (Diuretic-refractory)':
        return 3;
      default:
        return 1;
    }
  }

  static int getChildPughPointsBilirubin(double bilirubin) {
    if (bilirubin < 2.0) return 1;
    if (bilirubin <= 3.0) return 2;
    return 3;
  }

  static int getChildPughPointsAlbumin(double albumin) {
    if (albumin > 3.5) return 1;
    if (albumin >= 2.8) return 2;
    return 3;
  }

  static int getChildPughPointsPTINR(double ptInr) {
    if (ptInr < 1.7) return 1;
    if (ptInr <= 2.3) return 2;
    return 3;
  }

  static String interpretChildPugh(int score) {
    if (score <= 6) return 'Class A (Well-compensated disease, 1-year survival ~100%)';
    if (score <= 9) return 'Class B (Significant functional compromise, 1-year survival ~80%)';
    return 'Class C (Decompensated disease, 1-year survival ~45%)';
  }
}
