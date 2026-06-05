class VirgilDownloadOptions {
  const VirgilDownloadOptions({
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

class VirgilVoiceOption {
  const VirgilVoiceOption({
    required this.voiceId,
    required this.title,
    required this.subtitle,
  });

  final String voiceId;
  final String title;
  final String subtitle;
}

const virgilVoiceOptions = [
  VirgilVoiceOption(
    voiceId: 'af_heart',
    title: 'Heart',
    subtitle: '',
  ),
  VirgilVoiceOption(
    voiceId: 'af_bella',
    title: 'Bella',
    subtitle: '',
  ),
  VirgilVoiceOption(
    voiceId: 'af_sarah',
    title: 'Sarah',
    subtitle: '',
  ),
  VirgilVoiceOption(
    voiceId: 'am_adam',
    title: 'Adam',
    subtitle: '',
  ),
  VirgilVoiceOption(
    voiceId: 'am_michael',
    title: 'Michael',
    subtitle: '',
  ),
];
