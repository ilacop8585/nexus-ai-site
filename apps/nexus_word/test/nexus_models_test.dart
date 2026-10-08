import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_word/nexus_models.dart';

void main() {
  test('NexusAccess parses server fields', () {
    final access = NexusAccess.fromJson(<String, dynamic>{
      'user_id': 'u1',
      'display_name': 'NEXUS User',
      'staff_role': 'beta_tester',
      'unlimited': true,
      'plan': 'free',
      'credits': 42,
      'is_beta': true,
      'is_admin': false,
    });

    expect(access.userId, 'u1');
    expect(access.unlimited, isTrue);
    expect(access.credits, 42);
    expect(access.isBeta, isTrue);
  });

  test('active job state is recognized', () {
    final job = NexusJob.fromJson(<String, dynamic>{
      'id': 'j1',
      'status': 'running',
      'kind': 'general_file',
      'level': 'free',
      'input_summary': 'test',
      'charged_credits': 0,
    });

    expect(job.isActive, isTrue);
  });

  test('compute status exposes local-chat capability', () {
    const status = NexusComputeStatus(
      online: true,
      busy: false,
      capabilities: <String>{'local-chat', 'files'},
    );

    expect(status.hasLocalChat, isTrue);
  });
}
