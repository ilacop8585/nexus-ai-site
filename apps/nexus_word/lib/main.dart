import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'nexus_backend.dart';
import 'nexus_models.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NexusWordApp());
}

class NexusWordApp extends StatefulWidget {
  const NexusWordApp({super.key});

  @override
  State<NexusWordApp> createState() => _NexusWordAppState();
}

class _NexusWordAppState extends State<NexusWordApp> {
  late final NexusController controller;

  @override
  void initState() {
    super.initState();
    controller = NexusController(NexusBackend())..boot();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF8A7CFF);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NEXUS Word',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
          surface: const Color(0xFF0B0D12),
        ),
        scaffoldBackgroundColor: const Color(0xFF07090D),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          if (controller.booting) {
            return const _StartupScreen();
          }
          if (!controller.authenticated) {
            return AuthScreen(controller: controller);
          }
          return NexusShell(controller: controller);
        },
      ),
    );
  }
}

class NexusController extends ChangeNotifier {
  NexusController(this.backend);

  final NexusBackend backend;

  bool booting = true;
  bool authenticated = false;
  bool busy = false;
  bool refreshing = false;
  int section = 0;

  NexusAccess? access;
  NexusComputeStatus compute = NexusComputeStatus.offline;
  List<NexusConversation> conversations = const [];
  List<NexusMessage> messages = const [];
  List<NexusAttachment> library = const [];
  List<NexusJob> jobs = const [];
  String? currentConversationId;
  List<PlatformFile> selectedFiles = const [];
  String? error;
  String? notice;

  Timer? _jobsTimer;

  Future<void> boot() async {
    try {
      await backend.restoreSession();
      if (backend.hasStoredSession) {
        final session = await backend.getSession();
        if (session != null) {
          await backend.requireJwt();
          authenticated = true;
          await refreshAll();
        } else {
          await backend.clearSession();
        }
      }
    } catch (_) {
      await backend.clearSession();
      authenticated = false;
    } finally {
      booting = false;
      notifyListeners();
    }
  }

  Future<void> signIn(String email, String password) async {
    await _guard(() async {
      final session = await backend.signInEmail(email, password);
      if (session == null) {
        throw NexusException('Accesso non completato.');
      }
      authenticated = true;
      notice = 'Accesso NEXUS completato.';
      await refreshAll();
    });
  }

  Future<void> signUp(String name, String email, String password) async {
    await _guard(() async {
      final session = await backend.signUpEmail(name, email, password);
      if (session == null) {
        authenticated = false;
        notice =
            'Account creato. Se richiesta, completa la verifica email e poi accedi.';
        return;
      }
      authenticated = true;
      notice = 'Account NEXUS creato.';
      await refreshAll();
    });
  }

  Future<void> signOut() async {
    _jobsTimer?.cancel();
    await _guard(() async {
      await backend.signOut();
      authenticated = false;
      access = null;
      conversations = const [];
      messages = const [];
      library = const [];
      jobs = const [];
      currentConversationId = null;
      selectedFiles = const [];
    });
  }

  Future<void> refreshAll() async {
    refreshing = true;
    notifyListeners();
    try {
      final results = await Future.wait<dynamic>([
        backend.getMyAccess(),
        backend.listConversations(),
        backend.listLibrary(),
        backend.listJobs(),
        backend.getComputeStatus(),
      ]);
      access = results[0] as NexusAccess;
      conversations = results[1] as List<NexusConversation>;
      library = results[2] as List<NexusAttachment>;
      jobs = results[3] as List<NexusJob>;
      compute = results[4] as NexusComputeStatus;

      if (currentConversationId == null && conversations.isNotEmpty) {
        currentConversationId = conversations.first.id;
      }
      if (currentConversationId != null) {
        messages = await backend.listMessages(currentConversationId!);
      }
      _startJobsRefresh();
    } catch (e) {
      _setError(e);
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }

  void setSection(int value) {
    section = value;
    notifyListeners();
  }

  Future<void> newConversation() async {
    currentConversationId = null;
    messages = const [];
    selectedFiles = const [];
    section = 0;
    notice = 'Nuova conversazione pronta.';
    notifyListeners();
  }

  Future<void> openConversation(String id) async {
    if (busy) return;
    currentConversationId = id;
    section = 0;
    error = null;
    notifyListeners();
    try {
      messages = await backend.listMessages(id);
    } catch (e) {
      _setError(e);
    }
    notifyListeners();
  }

  Future<void> pickFiles() async {
    if (busy) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
      );
      if (result == null) return;
      if (result.files.length > NexusConfig.maxFilesPerJob) {
        throw NexusException(
          'Puoi allegare al massimo ${NexusConfig.maxFilesPerJob} file per job.',
        );
      }
      for (final file in result.files) {
        if (file.size > NexusConfig.maxFileBytes) {
          throw NexusException('${file.name} supera il limite di 250 MB.');
        }
      }
      selectedFiles = result.files;
      notice = '${selectedFiles.length} file selezionati.';
      notifyListeners();
    } catch (e) {
      _setError(e);
      notifyListeners();
    }
  }

  void clearFiles() {
    selectedFiles = const [];
    notifyListeners();
  }

  Future<void> send(String rawText) async {
    final text = rawText.trim();
    if (busy || (text.isEmpty && selectedFiles.isEmpty)) return;
    await _guard(() async {
      var conversationId = currentConversationId;
      if (conversationId == null) {
        conversationId = await backend.createConversation(
          text.isEmpty ? selectedFiles.first.name : text,
        );
        currentConversationId = conversationId;
        conversations = await backend.listConversations();
      }

      if (selectedFiles.isNotEmpty) {
        final files = List<PlatformFile>.from(selectedFiles);
        selectedFiles = const [];
        notice = 'Caricamento file su NEXUS…';
        notifyListeners();
        final jobId = await backend.submitFileJob(
          conversationId: conversationId,
          summary: text,
          files: files,
        );
        messages = await backend.listMessages(conversationId);
        library = await backend.listLibrary();
        jobs = await backend.listJobs();
        notice = 'Job NEXUS ${_short(jobId)} creato.';
        return;
      }

      final history = List<NexusMessage>.from(messages);
      await backend.insertUserMessage(conversationId, text);
      messages = [
        ...messages,
        NexusMessage(
          id: 'local-${DateTime.now().microsecondsSinceEpoch}',
          role: 'user',
          content: text,
          createdAt: DateTime.now(),
        ),
      ];
      notifyListeners();

      compute = await backend.getComputeStatus();
      final reply = await backend.sendChat(
        conversationId: conversationId,
        message: text,
        history: history,
        access: access,
        compute: compute,
      );
      messages = [
        ...messages,
        NexusMessage(
          id: 'local-${DateTime.now().microsecondsSinceEpoch}',
          role: 'assistant',
          content: reply.reply,
          createdAt: DateTime.now(),
          metadata: <String, dynamic>{
            'provider': reply.provider,
            'model': reply.model,
          },
        ),
      ];
      conversations = await backend.listConversations();
      notice = reply.provider == 'nexus-pc-worker'
          ? 'Risposta elaborata dalla flotta NEXUS PC.'
          : 'Risposta NEXUS completata.';
    });
  }

  Future<void> refreshJobs() async {
    try {
      jobs = await backend.listJobs();
      notifyListeners();
    } catch (_) {
      // Background refresh must not interrupt the user.
    }
  }

  Future<void> refreshLibrary() async {
    try {
      library = await backend.listLibrary();
    } catch (e) {
      _setError(e);
    }
    notifyListeners();
  }

  void clearMessage() {
    error = null;
    notice = null;
    notifyListeners();
  }

  void _startJobsRefresh() {
    _jobsTimer?.cancel();
    _jobsTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (authenticated && jobs.any((job) => job.isActive)) {
        refreshJobs();
      }
    });
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    error = null;
    notice = null;
    notifyListeners();
    try {
      await action();
    } catch (e) {
      _setError(e);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _setError(Object e) {
    error = e is NexusException ? e.message : e.toString();
  }

  static String _short(String id) =>
      id.length <= 8 ? id : id.substring(0, 8);

  @override
  void dispose() {
    _jobsTimer?.cancel();
    super.dispose();
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _NexusMark(size: 62),
            SizedBox(height: 24),
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Avvio NEXUS Word…'),
          ],
        ),
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({required this.controller, super.key});

  final NexusController controller;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool registerMode = false;
  bool obscure = true;

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (registerMode) {
      await widget.controller.signUp(
        nameController.text,
        emailController.text,
        passwordController.text,
      );
    } else {
      await widget.controller.signIn(
        emailController.text,
        passwordController.text,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: _NexusMark(size: 70)),
                      const SizedBox(height: 18),
                      Text(
                        'NEXUS Word',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        registerMode
                            ? 'Crea il tuo account NEXUS'
                            : 'Accedi al tuo spazio NEXUS',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 26),
                      if (registerMode) ...[
                        TextField(
                          controller: nameController,
                          textInputAction: TextInputAction.next,
                          decoration:
                              const InputDecoration(labelText: 'Nome'),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration:
                            const InputDecoration(labelText: 'Email'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: passwordController,
                        obscureText: obscure,
                        onSubmitted: (_) => c.busy ? null : submit(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => obscure = !obscure),
                            icon: Icon(
                              obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      if (c.error != null) ...[
                        const SizedBox(height: 14),
                        _NoticeBox(text: c.error!, error: true),
                      ],
                      if (c.notice != null) ...[
                        const SizedBox(height: 14),
                        _NoticeBox(text: c.notice!),
                      ],
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: c.busy ? null : submit,
                        icon: c.busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(registerMode
                                ? Icons.person_add_alt_1
                                : Icons.login),
                        label:
                            Text(registerMode ? 'Registrati' : 'Accedi'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: c.busy
                            ? null
                            : () => setState(() {
                                  registerMode = !registerMode;
                                  c.clearMessage();
                                }),
                        child: Text(registerMode
                            ? 'Hai già un account? Accedi'
                            : 'Non hai un account? Registrati'),
                      ),
                      const Divider(height: 28),
                      const Text(
                        'Google e Apple verranno collegati con autenticazione '
                        'nativa della piattaforma, non tramite WebView.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NexusShell extends StatelessWidget {
  const NexusShell({required this.controller, super.key});

  final NexusController controller;

  static const destinations = <NavigationDestination>[
    NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Chat'),
    NavigationDestination(
        icon: Icon(Icons.folder_outlined), label: 'Library'),
    NavigationDestination(icon: Icon(Icons.work_outline), label: 'Jobs'),
    NavigationDestination(
        icon: Icon(Icons.account_circle_outlined), label: 'Account'),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final body = switch (controller.section) {
      0 => ChatScreen(controller: controller),
      1 => LibraryScreen(controller: controller),
      2 => JobsScreen(controller: controller),
      _ => AccountScreen(controller: controller),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _NexusMark(size: 30),
            SizedBox(width: 10),
            Text('NEXUS Word'),
          ],
        ),
        actions: [
          _ComputePill(status: controller.compute),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Aggiorna',
            onPressed: controller.refreshing ? null : controller.refreshAll,
            icon: controller.refreshing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          if (controller.error != null || controller.notice != null)
            MaterialBanner(
              content: Text(controller.error ?? controller.notice!),
              leading: Icon(
                controller.error != null
                    ? Icons.error_outline
                    : Icons.check_circle_outline,
              ),
              actions: [
                TextButton(
                  onPressed: controller.clearMessage,
                  child: const Text('CHIUDI'),
                ),
              ],
            ),
          Expanded(
            child: wide
                ? Row(
                    children: [
                      NavigationRail(
                        selectedIndex: controller.section,
                        onDestinationSelected: controller.setSection,
                        labelType: NavigationRailLabelType.all,
                        leading: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: IconButton.filledTonal(
                            tooltip: 'Nuova chat',
                            onPressed: controller.newConversation,
                            icon: const Icon(Icons.add_comment_outlined),
                          ),
                        ),
                        destinations: destinations
                            .map(
                              (d) => NavigationRailDestination(
                                icon: d.icon,
                                label: Text(d.label),
                              ),
                            )
                            .toList(),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: body),
                    ],
                  )
                : body,
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: controller.section,
              onDestinationSelected: controller.setSection,
              destinations: destinations,
            ),
      floatingActionButton: !wide && controller.section == 0
          ? FloatingActionButton.small(
              onPressed: controller.newConversation,
              tooltip: 'Nuova chat',
              child: const Icon(Icons.add_comment_outlined),
            )
          : null,
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({required this.controller, super.key});

  final NexusController controller;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final composer = TextEditingController();
  final scroll = ScrollController();

  @override
  void dispose() {
    composer.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final value = composer.text;
    if (value.trim().isEmpty && widget.controller.selectedFiles.isEmpty) return;
    composer.clear();
    await widget.controller.send(value);
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (scroll.hasClients) {
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> showConversations() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: _ConversationList(
          controller: widget.controller,
          closeAfterSelect: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final desktop = MediaQuery.sizeOf(context).width >= 1050;

    final chat = Column(
      children: [
        _ChatHeader(
          controller: c,
          onOpenConversations: desktop ? null : showConversations,
        ),
        Expanded(
          child: c.messages.isEmpty
              ? const _EmptyChat()
              : ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                  itemCount: c.messages.length,
                  itemBuilder: (context, index) =>
                      _MessageBubble(message: c.messages[index]),
                ),
        ),
        if (c.selectedFiles.isNotEmpty)
          _SelectedFiles(
            files: c.selectedFiles,
            onClear: c.clearFiles,
          ),
        _Composer(
          controller: composer,
          busy: c.busy,
          onAttach: c.pickFiles,
          onSend: send,
        ),
      ],
    );

    if (!desktop) return chat;
    return Row(
      children: [
        SizedBox(
          width: 300,
          child: _ConversationList(controller: c),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: chat),
      ],
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.controller,
    this.onOpenConversations,
  });

  final NexusController controller;
  final VoidCallback? onOpenConversations;

  @override
  Widget build(BuildContext context) {
    NexusConversation? current;
    for (final item in controller.conversations) {
      if (item.id == controller.currentConversationId) {
        current = item;
        break;
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          if (onOpenConversations != null)
            IconButton(
              tooltip: 'Conversazioni',
              onPressed: onOpenConversations,
              icon: const Icon(Icons.history),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current?.title ?? 'Nuova conversazione',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  controller.access?.unlimited == true
                      ? 'NEXUS Auto · deep route disponibile'
                      : 'NEXUS Auto',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationList extends StatelessWidget {
  const _ConversationList({
    required this.controller,
    this.closeAfterSelect = false,
  });

  final NexusController controller;
  final bool closeAfterSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('Nuova chat'),
          onTap: () {
            controller.newConversation();
            if (closeAfterSelect) Navigator.pop(context);
          },
        ),
        const Divider(height: 1),
        Expanded(
          child: controller.conversations.isEmpty
              ? const Center(child: Text('Nessuna conversazione'))
              : ListView.builder(
                  itemCount: controller.conversations.length,
                  itemBuilder: (context, index) {
                    final item = controller.conversations[index];
                    return ListTile(
                      selected: item.id == controller.currentConversationId,
                      leading: const Icon(Icons.chat_bubble_outline),
                      title: Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: item.updatedAt == null
                          ? null
                          : Text(_date(item.updatedAt!)),
                      onTap: () {
                        controller.openConversation(item.id);
                        if (closeAfterSelect) Navigator.pop(context);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _NexusMark(size: 72),
              SizedBox(height: 20),
              Text(
                'Come posso aiutarti?',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 10),
              Text(
                'Chat, allegati, Library e job usano il tuo account NEXUS. '
                'Questa è l’app nativa: il sito non viene caricato dentro una WebView.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final NexusMessage message;

  @override
  Widget build(BuildContext context) {
    final user = message.isUser;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          color: user
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
        ),
        child: SelectableText(message.content),
      ),
    );
  }
}

class _SelectedFiles extends StatelessWidget {
  const _SelectedFiles({required this.files, required this.onClear});

  final List<PlatformFile> files;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ...files.map(
            (file) => Chip(
              avatar: const Icon(Icons.attach_file, size: 16),
              label: Text('${file.name} · ${_bytes(file.size)}'),
            ),
          ),
          TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.close, size: 18),
            label: const Text('Rimuovi'),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.busy,
    required this.onAttach,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onAttach;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton.filledTonal(
              tooltip: 'Allega file',
              onPressed: busy ? null : onAttach,
              icon: const Icon(Icons.attach_file),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 7,
                enabled: !busy,
                decoration: const InputDecoration(
                  hintText: 'Scrivi a NEXUS…',
                ),
                onSubmitted: (_) {\n                  if (!busy) onSend();\n                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Invia',
              onPressed: busy ? null : onSend,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_upward),
            ),
          ],
        ),
      ),
    );
  }
}

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({required this.controller, super.key});

  final NexusController controller;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: controller.refreshLibrary,
      child: controller.library.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 180),
                Icon(Icons.folder_open_outlined, size: 58),
                SizedBox(height: 14),
                Center(child: Text('La tua Library NEXUS è vuota.')),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: controller.library.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = controller.library[index];
                return ListTile(
                  leading: const Icon(Icons.insert_drive_file_outlined),
                  title: Text(item.filename),
                  subtitle: Text(
                    '${item.mimeType} · ${_bytes(item.sizeBytes)}'
                    '${item.createdAt == null ? '' : ' · ${_date(item.createdAt!)}'}',
                  ),
                );
              },
            ),
    );
  }
}

class JobsScreen extends StatelessWidget {
  const JobsScreen({required this.controller, super.key});

  final NexusController controller;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: controller.refreshJobs,
      child: controller.jobs.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 180),
                Icon(Icons.work_history_outlined, size: 58),
                SizedBox(height: 14),
                Center(child: Text('Nessun job NEXUS.')),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: controller.jobs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final job = controller.jobs[index];
                return ExpansionTile(
                  leading: job.isActive
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          job.status == 'completed'
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                        ),
                  title: Text(
                    job.summary.isEmpty ? job.kind : job.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${job.status} · ${job.kind}'
                    '${job.chargedCredits == 0 ? '' : ' · ${job.chargedCredits} crediti'}',
                  ),
                  childrenPadding:
                      const EdgeInsets.fromLTRB(24, 0, 24, 18),
                  children: [
                    if (job.output.isNotEmpty)
                      SelectableText(job.output)
                    else if (job.errorCode != null)
                      Text('Errore: ${job.errorCode}')
                    else
                      const Text('In elaborazione…'),
                  ],
                );
              },
            ),
    );
  }
}

class AccountScreen extends StatelessWidget {
  const AccountScreen({required this.controller, super.key});

  final NexusController controller;

  @override
  Widget build(BuildContext context) {
    final access = controller.access;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  children: [
                    const _NexusMark(size: 62),
                    const SizedBox(height: 14),
                    Text(
                      access?.displayName.isNotEmpty == true
                          ? access!.displayName
                          : 'Account NEXUS',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 20),
                    _AccountRow(
                      icon: Icons.workspace_premium_outlined,
                      label: 'Piano',
                      value: access?.plan ?? '—',
                    ),
                    _AccountRow(
                      icon: Icons.toll_outlined,
                      label: 'Crediti',
                      value: '${access?.credits ?? 0}',
                    ),
                    _AccountRow(
                      icon: Icons.route_outlined,
                      label: 'Routing',
                      value: access?.unlimited == true
                          ? 'NEXUS Auto · deep'
                          : 'NEXUS Auto',
                    ),
                    if (access?.isBeta == true)
                      const _AccountRow(
                        icon: Icons.science_outlined,
                        label: 'Beta',
                        value: 'Abilitato',
                      ),
                    if (access?.isAdmin == true)
                      const _AccountRow(
                        icon: Icons.admin_panel_settings_outlined,
                        label: 'Admin',
                        value: 'Abilitato',
                      ),
                    const Divider(height: 32),
                    ListTile(
                      leading: const Icon(Icons.security_outlined),
                      title: const Text('Credenziali provider'),
                      subtitle: const Text(
                        'Non sono memorizzate nell’app. Il client conserva '
                        'solo la sessione utente nel secure storage del sistema.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed:
                          controller.busy ? null : controller.signOut,
                      icon: const Icon(Icons.logout),
                      label: const Text('Esci da NEXUS'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ComputePill extends StatelessWidget {
  const _ComputePill({required this.status});

  final NexusComputeStatus status;

  @override
  Widget build(BuildContext context) {
    final label = status.busy
        ? 'Compute busy'
        : status.online
            ? 'Compute online'
            : 'Cloud';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            status.online ? Icons.circle : Icons.cloud_outlined,
            size: 10,
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _NexusMark extends StatelessWidget {
  const _NexusMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .27),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.tertiary,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .22),
            blurRadius: size * .35,
          ),
        ],
      ),
      child: Center(
        child: Text(
          'N',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: size * .55,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _NoticeBox extends StatelessWidget {
  const _NoticeBox({required this.text, this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: error
            ? Theme.of(context).colorScheme.errorContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Text(text),
    );
  }
}

String _date(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}

String _bytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(1)} GB';
}
