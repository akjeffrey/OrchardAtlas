import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, query, where, setDoc, updateDoc, deleteDoc, writeBatch, Timestamp, GeoPoint } from 'firebase/firestore';

const property = '00000000-0000-4000-8000-000000000001';
const item = '00000000-0000-4000-8000-000000000002';
const event = '00000000-0000-4000-8000-000000000003';
const taxon = '38a0fbb0-6a36-4a48-8d17-000000000003';
const propertyPath = `properties/${property}`;
const itemPath = `${propertyPath}/items/${item}`;
const eventPath = `${itemPath}/events/${event}`;
const now = Timestamp.now();
const plant = { schemaVersion: 1, kind: 'managedPlant', name: 'Apple 1', taxonId: taxon, location: new GeoPoint(51, 0), createdAt: now };
const harvest = { schemaVersion: 1, authorId: 'alice', type: 'harvest', occurredAt: now, recordedAt: now, activityDate: '2026-10-14', notes: '', harvest: { quantity: 2, unit: 'kg' } };
let env;
const db = (uid) => uid ? env.authenticatedContext(uid).firestore() : env.unauthenticatedContext().firestore();
before(async () => {
  env = await initializeTestEnvironment({ projectId: 'demo-orchard-atlas',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') } });
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await setDoc(doc(db('alice'), propertyPath), { schemaVersion: 1, ownerId: 'alice', name: 'Orchard', createdAt: now });
  await setDoc(doc(db('alice'), itemPath), plant);
});
test('owner can read and append, stranger and anonymous cannot', async () => {
  await assertSucceeds(getDoc(doc(db('alice'), itemPath)));
  await assertSucceeds(setDoc(doc(db('alice'), eventPath), harvest));
  for (const uid of ['bob', undefined]) {
    await assertFails(getDoc(doc(db(uid), itemPath)));
    await assertFails(setDoc(doc(db(uid), eventPath), { ...harvest, authorId: uid ?? 'anonymous' }));
  }
});
test('owner query succeeds, unfiltered property enumeration fails', async () => {
  await assertSucceeds(getDocs(query(collection(db('alice'), 'properties'), where('ownerId', '==', 'alice'))));
  await assertFails(getDocs(collection(db('alice'), 'properties')));
});
test('events cannot be overwritten or deleted', async () => {
  await assertSucceeds(setDoc(doc(db('alice'), eventPath), harvest));
  await assertFails(setDoc(doc(db('alice'), eventPath), harvest));
  await assertFails(updateDoc(doc(db('alice'), eventPath), { notes: 'Changed' }));
  await assertFails(deleteDoc(doc(db('alice'), eventPath)));
});
test('reject forged authors, invalid harvest, unknown fields and types', async () => {
  const cases = [
    { ...harvest, authorId: 'bob' },
    { ...harvest, harvest: { quantity: -1, unit: 'kg' } },
    { ...harvest, harvest: { quantity: 1.5, unit: 'count' } },
    { ...harvest, harvest: { quantity: Infinity, unit: 'kg' } },
    { ...harvest, harvest: { quantity: 2, unit: 'buckets' } },
    { ...harvest, type: 'note' },
    { ...harvest, type: 'unknown' },
    { ...harvest, secret: true },
    { ...harvest, activityDate: 'yesterday' },
    { ...harvest, schemaVersion: 2 },
  ];
  for (const data of cases) await assertFails(setDoc(doc(db('alice'), eventPath), data));
});
test('reject malformed items, forged property ownership and reserved paths', async () => {
  await assertFails(updateDoc(doc(db('alice'), itemPath), { taxonId: 'not-a-uuid' }));
  await assertFails(updateDoc(doc(db('alice'), itemPath), { createdAt: Timestamp.fromMillis(0) }));
  await assertFails(updateDoc(doc(db('alice'), propertyPath), { ownerId: 'bob' }));
  await assertFails(setDoc(doc(db('alice'), `${propertyPath}/members/bob`), { role: 'viewer' }));
  await assertFails(setDoc(doc(db('alice'), `${propertyPath}/tasks/${event}`), { title: 'Spray' }));
});
test('note without harvest is accepted; event needs an existing plant', async () => {
  const { harvest: ignored, ...note } = harvest;
  await assertSucceeds(setDoc(doc(db('alice'), eventPath), { ...note, type: 'note' }));
  await assertFails(setDoc(doc(db('alice'), `${propertyPath}/items/${event}/events/${item}`), harvest));
});

test('plant and dated planting activity can be created atomically', async () => {
  const store = db('alice');
  const newItem = `${propertyPath}/items/${event}`;
  const { harvest: ignored, ...base } = harvest;
  const batch = writeBatch(store);
  batch.set(doc(store, newItem), plant);
  batch.set(doc(store, `${newItem}/events/${item}`), { ...base, type: 'planting', activityDate: '2020-04-10' });
  await assertSucceeds(batch.commit());
});
test('custom taxonomy is owner scoped, append only and requires a supported icon', async () => {
  const path = `${propertyPath}/taxa/${event}`;
  const option = { schemaVersion: 1, name: 'Conference', rank: 'cultivar', parentId: taxon, symbol: 'pear' };
  await assertFails(setDoc(doc(db('bob'), path), option));
  await assertFails(setDoc(doc(db(), path), option));
  await assertFails(setDoc(doc(db('alice'), path), { ...option, symbol: 'unknown' }));
  await assertFails(setDoc(doc(db('alice'), path), { ...option, parentId: 'bad' }));
  await assertSucceeds(setDoc(doc(db('alice'), path), option));
  await assertSucceeds(getDoc(doc(db('alice'), path)));
  await assertFails(getDoc(doc(db('bob'), path)));
  await assertFails(updateDoc(doc(db('alice'), path), { name: 'Changed' }));
  await assertFails(deleteDoc(doc(db('alice'), path)));
});

test('metadata edits and archive preserve identity, position and planting date', async () => {
  await assertSucceeds(updateDoc(doc(db('alice'), itemPath), { name: 'Apple 12', rootstock: 'M.111', nursery: 'Local', notes: 'South slope', status: 'archived' }));
  await assertFails(updateDoc(doc(db('bob'), itemPath), { name: 'Stolen' }));
  await assertFails(updateDoc(doc(db(), itemPath), { status: 'active' }));
  for (const change of [{ taxonId: item }, { location: new GeoPoint(52, 2) }, { plantedOn: '2022-04-10' }, { accuracyMeters: 5 }, { status: 'unknown' }, { notes: 'x'.repeat(10001) }]) {
    await assertFails(updateDoc(doc(db('alice'), itemPath), change));
  }
  await assertSucceeds(updateDoc(doc(db('alice'), itemPath), { status: 'active' }));
  const path = `${propertyPath}/items/${event}`;
  const metadata = { ...plant, plantedOn: '2022-04-10', rootstock: 'M.111', nursery: '', notes: '', status: 'active', accuracyMeters: 6 };
  for (const change of [{ accuracyMeters: -1 }, { accuracyMeters: Infinity }, { plantedOn: 'yesterday' }, { rootstock: 'x'.repeat(501) }]) {
    await assertFails(setDoc(doc(db('alice'), path), { ...metadata, ...change }));
  }
  await assertSucceeds(setDoc(doc(db('alice'), path), metadata));
});
test('tasks support owner-only status changes and same-property plant targets', async () => {
  const path = `${propertyPath}/tasks/${event}`;
  const task = { schemaVersion: 1, title: 'Prune', notes: '', itemId: item, dueDate: '2026-10-16', status: 'open', createdAt: now };
  for (const uid of ['bob', undefined]) await assertFails(setDoc(doc(db(uid), path), task));
  for (const change of [{ title: '' }, { status: 'unknown' }, { dueDate: 'yesterday' }, { itemId: event }, { ownerId: 'bob' }]) {
    await assertFails(setDoc(doc(db('alice'), path), { ...task, ...change }));
  }
  await assertSucceeds(setDoc(doc(db('alice'), path), task));
  await assertSucceeds(getDocs(collection(db('alice'), `${propertyPath}/tasks`)));
  for (const uid of ['bob', undefined]) {
    await assertFails(getDoc(doc(db(uid), path)));
    await assertFails(updateDoc(doc(db(uid), path), { status: 'completed' }));
  }
  for (const status of ['completed', 'cancelled', 'open']) await assertSucceeds(updateDoc(doc(db('alice'), path), { status }));
  await assertFails(updateDoc(doc(db('alice'), path), { itemId: null }));
  await assertFails(updateDoc(doc(db('alice'), path), { createdAt: Timestamp.fromMillis(0) }));
  await assertFails(deleteDoc(doc(db('alice'), path)));
  await assertSucceeds(setDoc(doc(db('alice'), `${propertyPath}/tasks/${item}`), { ...task, itemId: null, dueDate: null }));
});
test('explicit phenology and lifecycle events remain append-only activities', async () => {
  const { harvest: ignored, ...base } = harvest;
  let index = 10;
  for (const type of ['budBreak', 'firstBloom', 'fullBloom', 'petalFall', 'fruitSet', 'pest', 'disease', 'damage', 'harvestStart', 'harvestEnd', 'died', 'observation']) {
    const id = `00000000-0000-4000-8000-${(++index).toString().padStart(12, '0')}`;
    await assertSucceeds(setDoc(doc(db('alice'), `${itemPath}/events/${id}`), { ...base, type }));
    await assertFails(updateDoc(doc(db('alice'), `${itemPath}/events/${id}`), { notes: 'Overwrite' }));
  }
});
