class NoveDownloadOptions {
  const NoveDownloadOptions({
    this.targetLang,
    this.voiceId,
  });

  final String? targetLang;
  final String? voiceId;

  bool get allTargetLangs => targetLang == null || targetLang!.trim().isEmpty;
  bool get allVoices => voiceId == null || voiceId!.trim().isEmpty;

  Map<String, dynamic> toJson() {
    return {
      'target_lang': targetLang,
      'voice_id': voiceId,
    };
  }
}

class NoveVoiceOption {
  const NoveVoiceOption({
    required this.voiceId,
    required this.title,
    required this.subtitle,
  });

  final String voiceId;
  final String title;
  final String subtitle;
}

const noveVoiceOptions = [
  NoveVoiceOption(
    voiceId: 'af_heart',
    title: 'Warm female',
    subtitle: 'af_heart',
  ),
  NoveVoiceOption(
    voiceId: 'af_nicole',
    title: 'Clear female',
    subtitle: 'af_nicole',
  ),
  NoveVoiceOption(
    voiceId: 'bm_george',
    title: 'British male',
    subtitle: 'bm_george',
  ),
  NoveVoiceOption(
    voiceId: 'am_michael',
    title: 'American male',
    subtitle: 'am_michael',
  ),
];
