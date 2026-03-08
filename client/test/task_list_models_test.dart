import 'package:client/src/models/server_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseTaskListResponse maps task items and refs', () {
    final parsed = parseTaskListResponse(<String, dynamic>{
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'doc_id': 'task-1',
          'ver_id': 'ver-1',
          'created_at': '2026-03-08T12:00:00Z',
          'title': 'Review processor prompt',
          'body_preview': 'Check the summarize node prompt.',
          'scope': 'team',
          'status': 'in_progress',
          'channel_doc_id': 'channel-1',
          'assignee_label': 'Planner Agent',
          'refs': <Map<String, dynamic>>[
            <String, dynamic>{
              'kind': 'processor',
              'node_id': 'n_enrich',
              'label': 'Summarize + Score',
            },
          ],
        },
      ],
    });

    expect(parsed, hasLength(1));
    expect(parsed.first.docId, 'task-1');
    expect(parsed.first.status, 'in_progress');
    expect(parsed.first.assigneeLabel, 'Planner Agent');
    expect(parsed.first.refs, hasLength(1));
    expect(parsed.first.refs.single.kind, 'processor');
    expect(parsed.first.refs.single.nodeId, 'n_enrich');
  });
}
