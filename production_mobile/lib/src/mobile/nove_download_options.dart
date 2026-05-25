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
    title: 'Heart',
    subtitle: '',
  ),
  NoveVoiceOption(
    voiceId: 'af_bella',
    title: 'Bella',
    subtitle: '',
  ),
  NoveVoiceOption(
    voiceId: 'af_sarah',
    title: 'Sarah',
    subtitle: '',
  ),
  NoveVoiceOption(
    voiceId: 'am_adam',
    title: 'Adam',
    subtitle: '',
  ),
  NoveVoiceOption(
    voiceId: 'am_michael',
    title: 'Michael',
    subtitle: '',
  ),
];
