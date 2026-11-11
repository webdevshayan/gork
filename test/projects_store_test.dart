import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gork/services/projects_store.dart';

void main() {
  Future<ProjectsStore> make() async {
    SharedPreferences.setMockInitialValues({});
    return ProjectsStore(await SharedPreferences.getInstance());
  }

  test('create, update via copyWith, list sorted by updatedAt', () async {
    final store = await make();

    final p1 = Project(
      id: '1',
      title: 'Thesis',
      notes: 'Chapter 1 done',
      files: const [ProjectFile('outline.md', '# Outline')],
      createdAt: 100,
      updatedAt: 100,
    );
    await store.save(p1);

    final p2 = Project(id: '2', title: 'Flat search', notes: '', files: const [], createdAt: 200, updatedAt: 200);
    await store.save(p2);

    expect(store.all().map((p) => p.id), ['2', '1']); // newest first

    await store.save(p1.copyWith(notes: 'Chapter 1 and 2 done', updatedAt: 300));
    expect(store.all().first.id, '1');
    expect(store.byId('1')!.notes, 'Chapter 1 and 2 done');
    expect(store.byId('1')!.title, 'Thesis'); // unchanged
    expect(store.byId('1')!.files.length, 1);
  });

  test('delete removes only the target project', () async {
    final store = await make();
    await store.save(Project(
        id: 'a', title: 'A', notes: '', files: const [], createdAt: 1, updatedAt: 1));
    await store.save(Project(
        id: 'b', title: 'B', notes: '', files: const [], createdAt: 2, updatedAt: 2));
    await store.delete('a');
    expect(store.all().map((p) => p.id), ['b']);
  });

  test('json round-trip keeps files', () async {
    final store = await make();
    await store.save(Project(
      id: 'rt',
      title: 'Round trip',
      notes: 'n',
      files: const [
        ProjectFile('a.md', 'content a'),
        ProjectFile('b.txt', 'content b'),
      ],
      createdAt: 9,
      updatedAt: 9,
    ));
    final loaded = store.byId('rt')!;
    expect(loaded.files.map((f) => f.name), ['a.md', 'b.txt']);
    expect(loaded.files.first.content, 'content a');
  });
}
