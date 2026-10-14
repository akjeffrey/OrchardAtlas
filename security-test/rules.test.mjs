import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, query, where, setDoc, updateDoc, deleteDoc, Timestamp, GeoPoint } from 'firebase/firestore';

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
