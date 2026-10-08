import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'nexus_models.dart';

class NexusConfig {
  static const neonBase =
      'https://ep-sparkling-forest-b2v7x4ux.c-6.eu-central-1.aws.neon.tech/neondb';
  static const authBase =
      'https://ep-sparkling-forest-b2v7x4ux.neonauth.c-6.eu-central-1.aws.neon.tech/neondb/auth';
  static const dataApiBase =
      'https://ep-sparkling-forest-b2v7x4ux.apirest.c-6.eu-central-1.aws.neon.tech/neondb/rest/v1';
  static const routerUrl =
      'https://nexus-ai-router.ilario-coppola.workers.dev/chat';
  static const filesUrl =
      'https://br-jolly-scene-b2wyu6gt-nexusfiles.compute.c-6.eu-central-1.aws.neon.tech/';
  static const statusUrl =
      'https://br-jolly-scene-b2wyu6gt-nexusstatus.compute.c-6.eu-central-1.aws.neon.tech/';
  static const webCallback = 'https://nexusword.it/';

  static const int maxFilesPerJob = 5;
  static const int maxFileBytes = 250 * 1024 * 1024;
}

class NexusException implements Exception {
  NexusException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class NexusBackend {
  NexusBackend({HttpClient? httpClient})
      : _http = httpClient ?? HttpClient();

  final HttpClient _http;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  static const _jwtKey = 'nexus.auth.jwt';
  static const _cookiesKey = 'nexus.auth.cookies';

  String? _jwt;
  final Map<String, String> _cookies = <String, String>{};

  bool get hasStoredSession =>
      (_jwt != null && _jwt!.isNotEmpty) || _cookies.isNotEmpty;

  Future<void> restoreSession() async {
    _jwt = await _secureStorage.read(key: _jwtKey);
    final rawCookies = await _secureStorage.read(key: _cookiesKey);
    if (rawCookies != null && rawCookies.isNotEmpty) {
      try {
        final value = jsonDecode(rawCookies);
        if (value is Map) {
          _cookies
            ..clear()
            ..addAll(value.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            ));
        }
      } catch (_) {
        _cookies.clear();
      }
    }
  }

  Future<void> clearSession() async {
    _jwt = null;
    _cookies.clear();
    await _secureStorage.delete(key: _jwtKey);
    await _secureStorage.delete(key: _cookiesKey);
  }

  Future<Map<String, dynamic>?> signInEmail(
    String email,
    String password,
  ) async {
    await _authRequest(
      'POST',
      '/sign-in/email',
      body: <String, dynamic>{
        'email': email.trim(),
        'password': password,
        'rememberMe': true,
        'callbackURL': NexusConfig.webCallback,
      },
    );
    await _refreshJwt();
    return getSession();
  }

  Future<Map<String, dynamic>?> signUpEmail(
    String name,
    String email,
    String password,
  ) async {
    await _authRequest(
      'POST',
      '/sign-up/email',
      body: <String, dynamic>{
        'name': name.trim(),
        'email': email.trim(),
        'password': password,
        'callbackURL': NexusConfig.webCallback,
      },
    );
    await _refreshJwt();
    return getSession();
  }

  Future<void> signOut() async {
    try {
      await _authRequest('POST', '/sign-out', body: const <String, dynamic>{});
    } finally {
      await clearSession();
    }
  }

  Future<Map<String, dynamic>?> getSession() async {
    final data = await _authRequest('GET', '/get-session');
    if (data == null) return null;
    if (data is Map<String, dynamic>) return data;
    return null;
  }

  Future<String> requireJwt() async {
    if (_jwt == null || _jwt!.isEmpty) {
      await _refreshJwt();
    }
    if (_jwt == null || _jwt!.isEmpty) {
      throw NexusException('Sessione NEXUS non autenticata.');
    }
    return _jwt!;
  }

  Future<void> _refreshJwt() async {
    try {
      final tokenData = await _authRequest('GET', '/token');
      if (tokenData is Map && tokenData['token'] != null) {
        await _storeJwt(tokenData['token'].toString());
        return;
      }
    } catch (_) {
      // getSession also exposes set-auth-jwt when the JWT plugin is active.
    }
    await _authRequest('GET', '/get-session');
  }

  Future<dynamic> _authRequest(
    String method,
    String path, {
    Object? body,
  }) async {
    final uri = Uri.parse('${NexusConfig.authBase}$path');
    final request = await _http.openUrl(method, uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    if (_cookies.isNotEmpty) {
      request.headers.set(
        HttpHeaders.cookieHeader,
        _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
      );
    }
    if (body != null) request.write(jsonEncode(body));

    final response = await request.close().timeout(const Duration(seconds: 25));
    await _captureAuth(response);
    final text = await utf8.decoder.bind(response).join();
    final decoded = text.trim().isEmpty ? null : _tryJson(text);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NexusException(
        _errorMessage(decoded, 'Autenticazione NEXUS non riuscita.'),
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  Future<void> _captureAuth(HttpClientResponse response) async {
    final jwt = response.headers.value('set-auth-jwt');
    if (jwt != null && jwt.isNotEmpty) await _storeJwt(jwt);

    var cookiesChanged = false;
    for (final cookie in response.cookies) {
      if (cookie.value.isEmpty) {
        _cookies.remove(cookie.name);
      } else {
        _cookies[cookie.name] = cookie.value;
      }
      cookiesChanged = true;
    }
    if (cookiesChanged) {
      await _secureStorage.write(
        key: _cookiesKey,
        value: jsonEncode(_cookies),
      );
    }
  }

  Future<void> _storeJwt(String token) async {
    _jwt = token;
    await _secureStorage.write(key: _jwtKey, value: token);
  }

  Future<NexusAccess> getMyAccess() async {
    final data = await rpc('nexus_get_my_access');
    final row = _firstObject(data);
    if (row == null) {
      throw NexusException('Profilo NEXUS non disponibile.');
    }
    return NexusAccess.fromJson(row);
  }

  Future<List<NexusConversation>> listConversations() async {
    final rows = await _tableGet(
      'nexus_conversations',
      <String, String>{
        'select': 'id,title,level,updated_at',
        'order': 'updated_at.desc',
        'limit': '100',
      },
    );
    return _objects(rows).map(NexusConversation.fromJson).toList();
  }

  Future<String> createConversation(String firstText) async {
    final title = firstText.trim().replaceAll(RegExp(r'\s+'), ' ');
    final data = await _tableRequest(
      'POST',
      'nexus_conversations',
      query: const <String, String>{'select': 'id,title,level,updated_at'},
      body: <String, dynamic>{
        'title': title.isEmpty
            ? 'Nuova chat'
            : title.substring(0, title.length > 72 ? 72 : title.length),
        'level': 'free',
      },
      preferRepresentation: true,
    );
    final row = _firstObject(data);
    if (row == null || row['id'] == null) {
      throw NexusException('Creazione conversazione non riuscita.');
    }
    return row['id'].toString();
  }

  Future<List<NexusMessage>> listMessages(String conversationId) async {
    final rows = await _tableGet(
      'nexus_messages',
      <String, String>{
        'select': 'id,role,content,metadata,created_at',
        'conversation_id': 'eq.$conversationId',
        'order': 'created_at.asc',
        'limit': '500',
      },
    );
    return _objects(rows).map(NexusMessage.fromJson).toList();
  }

  Future<void> insertUserMessage(
    String conversationId,
    String content, {
    int attachmentCount = 0,
  }) async {
    await _tableRequest(
      'POST',
      'nexus_messages',
      body: <String, dynamic>{
        'conversation_id': conversationId,
        'role': 'user',
        'content': content,
        'metadata': <String, dynamic>{
          'level': 'free',
          'attachment_count': attachmentCount,
          'client': 'nexus-word-native',
        },
      },
    );
    await touchConversation(conversationId);
  }

  Future<void> touchConversation(String conversationId) async {
    await _tableRequest(
      'PATCH',
      'nexus_conversations',
      query: <String, String>{'id': 'eq.$conversationId'},
      body: <String, dynamic>{
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  Future<List<NexusAttachment>> listLibrary() async {
    final rows = await _tableGet(
      'nexus_attachments',
      const <String, String>{
        'select': '*',
        'limit': '200',
      },
    );
    final values = _objects(rows).map(NexusAttachment.fromJson).toList();
    values.sort((a, b) =>
        (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
          a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        ));
    return values;
  }

  Future<List<NexusJob>> listJobs() async {
    final rows = await _tableGet(
      'nexus_jobs',
      const <String, String>{
        'select':
            'id,status,kind,level,input_summary,output_summary,error_code,charged_credits,created_at',
        'order': 'created_at.desc',
        'limit': '100',
      },
    );
    return _objects(rows).map(NexusJob.fromJson).toList();
  }

  Future<NexusComputeStatus> getComputeStatus() async {
    try {
      final value = await _plainJson(
        'GET',
        Uri.parse(NexusConfig.statusUrl),
        timeout: const Duration(seconds: 8),
      );
      if (value is! Map) return NexusComputeStatus.offline;
      final workers = value['workers'];
      if (workers is! List) return NexusComputeStatus.offline;
      Map? active;
      for (final worker in workers) {
        if (worker is Map && worker['online'] == true) {
          active = worker;
          break;
        }
      }
      if (active == null) return NexusComputeStatus.offline;
      final capabilities = <String>{};
      final rawCaps = active['capabilities'];
      if (rawCaps is List) {
        capabilities.addAll(rawCaps.map((e) => e.toString()));
      }
      return NexusComputeStatus(
        online: true,
        busy: active['status'] == 'busy',
        capabilities: capabilities,
      );
    } catch (_) {
      return NexusComputeStatus.offline;
    }
  }

  Future<NexusChatReply> cloudChat(
    String message,
    List<NexusMessage> history,
  ) async {
    final jwt = await requireJwt();
    final historyPayload = history
        .takeLast(20)
        .map((m) => <String, String>{
              'role': m.role,
              'content': m.content,
            })
        .toList();

    final data = await _plainJson(
      'POST',
      Uri.parse(NexusConfig.routerUrl),
      headers: <String, String>{'Authorization': 'Bearer $jwt'},
      body: <String, dynamic>{
        'message': message,
        'level': 'free',
        'history': historyPayload,
      },
      timeout: const Duration(seconds: 22),
    );
    if (data is! Map || data['ok'] != true || data['reply'] == null) {
      throw NexusException(
        data is Map && data['error'] != null
            ? data['error'].toString()
            : 'NEXUS cloud temporaneamente non disponibile.',
      );
    }
    return NexusChatReply(
      reply: data['reply'].toString(),
      provider: data['provider']?.toString(),
      model: data['model']?.toString(),
      fallbackUsed: data['fallbackUsed'] == true,
    );
  }

  Future<NexusChatReply> localPcChat(
    String conversationId,
    String message,
    List<NexusMessage> history,
  ) async {
    final context = history
        .takeLast(8)
        .map(
          (m) =>
              '${m.isUser ? 'UTENTE' : 'ASSISTENTE'}: '
              '${m.content.length > 1200 ? m.content.substring(0, 1200) : m.content}',
        )
        .join('\n');

    final prompt = <String>[
      'Sei NEXUS AI. Rispondi nella stessa lingua dell utente; se scrive in italiano, usa italiano naturale.',
      'Dai una risposta completa e concreta. Non inventare azioni non eseguite.',
      if (context.isNotEmpty) 'CONTESTO RECENTE:\n$context',
      'RICHIESTA UTENTE:\n$message',
    ].join('\n\n');
    final bounded =
        prompt.length > 11900 ? prompt.substring(0, 11900) : prompt;

    final created = await rpc(
      'nexus_create_chat_local_job',
      <String, dynamic>{
        'p_conversation_id': conversationId,
        'p_prompt': bounded,
      },
    );
    final row = _firstObject(created);
    final jobId = row?['job_id']?.toString();
    if (jobId == null || jobId.isEmpty) {
      throw NexusException('Job NEXUS PC non creato.');
    }

    for (var i = 0; i < 110; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final result = await _tableGet(
        'nexus_jobs',
        <String, String>{
          'select':
              'status,output_summary,error_code,worker_id,completed_at',
          'id': 'eq.$jobId',
          'limit': '1',
        },
      );
      final job = _firstObject(result);
      final status = job?['status']?.toString();
      if (status == 'completed') {
        final reply = (job?['output_summary'] ?? '').toString().trim();
        if (reply.isEmpty) {
          throw NexusException('Il worker NEXUS ha restituito una risposta vuota.');
        }
        return NexusChatReply(
          reply: reply,
          provider: 'nexus-pc-worker',
          model: row?['resolved_level'] == 'deep'
              ? 'NEXUS PC deep route'
              : 'NEXUS PC local route',
          fallbackUsed: true,
        );
      }
      if (status == 'failed' || status == 'cancelled') {
        throw NexusException(
          job?['error_code']?.toString() ?? 'NEXUS PC job fallito.',
        );
      }
    }
    throw NexusException('Timeout del worker NEXUS PC.');
  }

  Future<NexusChatReply> sendChat({
    required String conversationId,
    required String message,
    required List<NexusMessage> history,
    required NexusAccess? access,
    required NexusComputeStatus compute,
  }) async {
    final preferPc = access?.unlimited == true && compute.hasLocalChat;
    late NexusChatReply reply;

    if (preferPc) {
      try {
        reply = await localPcChat(conversationId, message, history);
      } catch (_) {
        reply = await cloudChat(message, history);
      }
    } else {
      try {
        reply = await cloudChat(message, history);
      } catch (cloudError) {
        if (!compute.hasLocalChat) rethrow;
        reply = await localPcChat(conversationId, message, history);
      }
    }

    if (reply.provider != 'nexus-pc-worker') {
      final metadata = <String, dynamic>{
        'level': 'free',
        'model': reply.model,
        'provider': reply.provider,
        'fallback_used': reply.fallbackUsed,
        'client': 'nexus-word-native',
      };
      try {
        await rpc(
          'nexus_store_assistant_message',
          <String, dynamic>{
            'p_conversation_id': conversationId,
            'p_content': reply.reply,
            'p_metadata': metadata,
          },
        );
      } catch (_) {
        await _tableRequest(
          'POST',
          'nexus_messages',
          body: <String, dynamic>{
            'conversation_id': conversationId,
            'role': 'assistant',
            'content': reply.reply,
            'metadata': metadata,
          },
        );
      }
    }
    await touchConversation(conversationId);
    return reply;
  }

  Future<String> submitFileJob({
    required String conversationId,
    required String summary,
    required List<PlatformFile> files,
  }) async {
    if (files.isEmpty) {
      throw NexusException('Nessun file selezionato.');
    }
    if (files.length > NexusConfig.maxFilesPerJob) {
      throw NexusException(
        'Massimo ${NexusConfig.maxFilesPerJob} file per job.',
      );
    }

    for (final file in files) {
      if (file.path == null) {
        throw NexusException('Percorso file non disponibile: ${file.name}');
      }
      if (file.size > NexusConfig.maxFileBytes) {
        throw NexusException('${file.name} supera il limite di 250 MB.');
      }
    }

    final attachmentIds = <String>[];
    for (final file in files) {
      attachmentIds.add(await uploadOne(conversationId, file));
    }

    final cleanSummary = summary.trim().isEmpty
        ? 'Processa ${files.map((e) => e.name).join(', ')}'
        : summary.trim();

    await insertUserMessage(
      conversationId,
      cleanSummary,
      attachmentCount: files.length,
    );

    final kind = _jobKind(files);
    final data = await rpc(
      'nexus_create_job',
      <String, dynamic>{
        'p_conversation_id': conversationId,
        'p_kind': kind,
        'p_level': 'free',
        'p_attachment_ids': attachmentIds,
        'p_summary': cleanSummary,
      },
    );
    final row = _firstObject(data);
    final id = row?['job_id']?.toString() ?? row?['id']?.toString();
    if (id == null || id.isEmpty) {
      throw NexusException('Job file NEXUS non creato.');
    }
    return id;
  }

  Future<String> uploadOne(
    String conversationId,
    PlatformFile platformFile,
  ) async {
    final path = platformFile.path;
    if (path == null) throw NexusException('File non leggibile.');
    final file = File(path);
    final mime = _mimeFor(platformFile.name);

    final ticketData = await rpc(
      'nexus_create_upload_ticket',
      <String, dynamic>{
        'p_conversation_id': conversationId,
        'p_filename': platformFile.name,
        'p_mime': mime,
        'p_size': platformFile.size,
      },
    );
    final ticket = _firstObject(ticketData);
    final ticketId = ticket?['ticket_id']?.toString();
    if (ticketId == null || ticketId.isEmpty) {
      throw NexusException('Ticket upload NEXUS mancante.');
    }

    final presigned = await _plainJson(
      'POST',
      Uri.parse('${NexusConfig.filesUrl}presign'),
      body: <String, dynamic>{'ticketId': ticketId},
      timeout: const Duration(seconds: 25),
    );
    if (presigned is! Map || presigned['uploadUrl'] == null) {
      throw NexusException('Presign upload NEXUS non riuscito.');
    }

    final uploadUri = Uri.parse(presigned['uploadUrl'].toString());
    final request = await _http.putUrl(uploadUri);
    request.headers.set(HttpHeaders.contentTypeHeader, mime);
    await request.addStream(file.openRead());
    final uploadResponse =
        await request.close().timeout(const Duration(minutes: 5));
    await uploadResponse.drain<void>();
    if (uploadResponse.statusCode < 200 || uploadResponse.statusCode >= 300) {
      throw NexusException(
        'Upload storage fallito (HTTP ${uploadResponse.statusCode}).',
      );
    }

    final completed = await _plainJson(
      'POST',
      Uri.parse('${NexusConfig.filesUrl}complete'),
      body: <String, dynamic>{'ticketId': ticketId},
      timeout: const Duration(seconds: 25),
    );
    if (completed is! Map || completed['attachmentId'] == null) {
      throw NexusException('Verifica upload NEXUS non riuscita.');
    }
    return completed['attachmentId'].toString();
  }

  Future<dynamic> rpc(
    String functionName, [
    Map<String, dynamic> body = const <String, dynamic>{},
  ]) async {
    return _dataRequest(
      'POST',
      '/rpc/$functionName',
      body: body,
    );
  }

  Future<dynamic> _tableGet(
    String table,
    Map<String, String> query,
  ) =>
      _dataRequest('GET', '/$table', query: query);

  Future<dynamic> _tableRequest(
    String method,
    String table, {
    Map<String, String> query = const <String, String>{},
    Object? body,
    bool preferRepresentation = false,
  }) =>
      _dataRequest(
        method,
        '/$table',
        query: query,
        body: body,
        preferRepresentation: preferRepresentation,
      );

  Future<dynamic> _dataRequest(
    String method,
    String path, {
    Map<String, String> query = const <String, String>{},
    Object? body,
    bool preferRepresentation = false,
  }) async {
    final jwt = await requireJwt();
    final base = Uri.parse('${NexusConfig.dataApiBase}$path');
    final uri = base.replace(queryParameters: query.isEmpty ? null : query);
    final request = await _http.openUrl(method, uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $jwt');
    request.headers.set('Accept-Profile', 'public');
    request.headers.set('Content-Profile', 'public');
    if (preferRepresentation) {
      request.headers.set('Prefer', 'return=representation');
    }
    if (body != null) request.write(jsonEncode(body));

    final response = await request.close().timeout(const Duration(seconds: 30));
    final text = await utf8.decoder.bind(response).join();
    final decoded = text.trim().isEmpty ? null : _tryJson(text);
    if (response.statusCode == 401 ||
        (response.statusCode == 400 &&
            text.contains('missing authentication credentials'))) {
      _jwt = null;
      await _secureStorage.delete(key: _jwtKey);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NexusException(
        _errorMessage(decoded, 'Richiesta NEXUS non riuscita.'),
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  Future<dynamic> _plainJson(
    String method,
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
    Object? body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final request = await _http.openUrl(method, uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (body != null) {
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    }
    headers.forEach(request.headers.set);
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close().timeout(timeout);
    final text = await utf8.decoder.bind(response).join();
    final decoded = text.trim().isEmpty ? null : _tryJson(text);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NexusException(
        _errorMessage(decoded, 'Servizio NEXUS non disponibile.'),
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  String _jobKind(List<PlatformFile> files) {
    final ext = files.length == 1
        ? files.first.extension?.toLowerCase()
        : null;
    if (ext != null &&
        const {'pdf', 'doc', 'docx', 'txt', 'md', 'rtf'}.contains(ext)) {
      return 'document_task';
    }
    if (ext != null &&
        const {
          'dart',
          'js',
          'ts',
          'py',
          'java',
          'kt',
          'swift',
          'c',
          'cpp',
          'h',
          'html',
          'css',
          'json',
          'yaml',
          'yml',
          'sql'
        }.contains(ext)) {
      return 'code_task';
    }
    if (ext != null &&
        const {'zip', 'rar', '7z', 'tar', 'gz', 'bz2'}.contains(ext)) {
      return 'archive_task';
    }
    return 'general_file';
  }

  String _mimeFor(String filename) {
    final name = filename.toLowerCase();
    if (name.endsWith('.pdf')) return 'application/pdf';
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    if (name.endsWith('.gif')) return 'image/gif';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.json')) return 'application/json';
    if (name.endsWith('.txt') || name.endsWith('.md')) return 'text/plain';
    if (name.endsWith('.zip')) return 'application/zip';
    return 'application/octet-stream';
  }

  dynamic _tryJson(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return text;
    }
  }

  String _errorMessage(dynamic decoded, String fallback) {
    if (decoded is Map) {
      for (final key in const ['message', 'error', 'detail', 'hint']) {
        final value = decoded[key];
        if (value != null && value.toString().trim().isNotEmpty) {
          return value.toString();
        }
      }
    }
    if (decoded is String && decoded.trim().isNotEmpty) return decoded;
    return fallback;
  }

  List<Map<String, dynamic>> _objects(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Map<String, dynamic>? _firstObject(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    final objects = _objects(value);
    return objects.isEmpty ? null : objects.first;
  }
}

extension<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final values = toList(growable: false);
    if (values.length <= count) return values;
    return values.sublist(values.length - count);
  }
}
