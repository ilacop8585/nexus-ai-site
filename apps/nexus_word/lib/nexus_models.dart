class NexusAccess {
  const NexusAccess({
    required this.userId,
    required this.displayName,
    required this.staffRole,
    required this.unlimited,
    required this.plan,
    required this.credits,
    required this.isBeta,
    required this.isAdmin,
  });

  final String userId;
  final String displayName;
  final String? staffRole;
  final bool unlimited;
  final String plan;
  final int credits;
  final bool isBeta;
  final bool isAdmin;

  factory NexusAccess.fromJson(Map<String, dynamic> json) => NexusAccess(
        userId: '${json['user_id'] ?? ''}',
        displayName: '${json['display_name'] ?? ''}',
        staffRole: json['staff_role']?.toString(),
        unlimited: json['unlimited'] == true,
        plan: '${json['plan'] ?? 'free'}',
        credits: (json['credits'] as num?)?.toInt() ?? 0,
        isBeta: json['is_beta'] == true,
        isAdmin: json['is_admin'] == true,
      );
}

class NexusConversation {
  const NexusConversation({
    required this.id,
    required this.title,
    required this.level,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String level;
  final DateTime? updatedAt;

  factory NexusConversation.fromJson(Map<String, dynamic> json) =>
      NexusConversation(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? 'Nuova chat'}',
        level: '${json['level'] ?? 'free'}',
        updatedAt: DateTime.tryParse('${json['updated_at'] ?? ''}'),
      );
}

class NexusMessage {
  const NexusMessage({
    required this.id,
    required this.role,
    required this.content,
    this.createdAt,
    this.metadata = const <String, dynamic>{},
  });

  final String id;
  final String role;
  final String content;
  final DateTime? createdAt;
  final Map<String, dynamic> metadata;

  bool get isUser => role == 'user';

  factory NexusMessage.fromJson(Map<String, dynamic> json) => NexusMessage(
        id: '${json['id'] ?? ''}',
        role: '${json['role'] ?? 'assistant'}',
        content: '${json['content'] ?? ''}',
        createdAt: DateTime.tryParse('${json['created_at'] ?? ''}'),
        metadata: json['metadata'] is Map
            ? Map<String, dynamic>.from(json['metadata'] as Map)
            : const <String, dynamic>{},
      );
}

class NexusJob {
  const NexusJob({
    required this.id,
    required this.status,
    required this.kind,
    required this.level,
    required this.summary,
    required this.output,
    required this.errorCode,
    required this.chargedCredits,
    required this.createdAt,
  });

  final String id;
  final String status;
  final String kind;
  final String level;
  final String summary;
  final String output;
  final String? errorCode;
  final int chargedCredits;
  final DateTime? createdAt;

  bool get isActive =>
      const {'queued', 'claimed', 'running', 'qa'}.contains(status);

  factory NexusJob.fromJson(Map<String, dynamic> json) => NexusJob(
        id: '${json['id'] ?? ''}',
        status: '${json['status'] ?? ''}',
        kind: '${json['kind'] ?? ''}',
        level: '${json['level'] ?? ''}',
        summary: '${json['input_summary'] ?? ''}',
        output: '${json['output_summary'] ?? ''}',
        errorCode: json['error_code']?.toString(),
        chargedCredits: (json['charged_credits'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse('${json['created_at'] ?? ''}'),
      );
}

class NexusAttachment {
  const NexusAttachment({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.sizeBytes,
    required this.createdAt,
  });

  final String id;
  final String filename;
  final String mimeType;
  final int sizeBytes;
  final DateTime? createdAt;

  factory NexusAttachment.fromJson(Map<String, dynamic> json) =>
      NexusAttachment(
        id: '${json['id'] ?? ''}',
        filename:
            '${json['filename'] ?? json['original_filename'] ?? 'file'}',
        mimeType: '${json['mime_type'] ?? 'application/octet-stream'}',
        sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse('${json['created_at'] ?? ''}'),
      );
}

class NexusComputeStatus {
  const NexusComputeStatus({
    required this.online,
    required this.busy,
    required this.capabilities,
  });

  final bool online;
  final bool busy;
  final Set<String> capabilities;

  bool get hasLocalChat => capabilities.contains('local-chat');

  static const offline = NexusComputeStatus(
    online: false,
    busy: false,
    capabilities: <String>{},
  );
}

class NexusChatReply {
  const NexusChatReply({
    required this.reply,
    required this.provider,
    required this.model,
    required this.fallbackUsed,
  });

  final String reply;
  final String? provider;
  final String? model;
  final bool fallbackUsed;
}
