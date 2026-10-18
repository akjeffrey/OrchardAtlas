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
test('owners edit and delete activities while identity stays immutable', async () => {
  await assertSucceeds(setDoc(doc(db('alice'), eventPath), harvest));
  await assertSucceeds(setDoc(doc(db('alice'), eventPath), harvest));
  await assertSucceeds(updateDoc(doc(db('alice'), eventPath), { notes: 'Changed' }));
  await assertFails(updateDoc(doc(db('alice'), eventPath), { authorId: 'bob' }));
  await assertFails(updateDoc(doc(db('alice'), eventPath), { recordedAt: Timestamp.fromMillis(0) }));
  await assertSucceeds(deleteDoc(doc(db('alice'), eventPath)));
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
test('custom taxonomy edits remain owner scoped with immutable hierarchy', async () => {
  const path = `${propertyPath}/taxa/${event}`;
  const option = { schemaVersion: 1, name: 'Conference', rank: 'cultivar', parentId: taxon, symbol: 'pear' };
  await assertFails(setDoc(doc(db('bob'), path), option));
  await assertFails(setDoc(doc(db(), path), option));
  await assertFails(setDoc(doc(db('alice'), path), { ...option, symbol: 'unknown' }));
  await assertFails(setDoc(doc(db('alice'), path), { ...option, parentId: 'bad' }));
  await assertSucceeds(setDoc(doc(db('alice'), path), option));
  await assertSucceeds(getDoc(doc(db('alice'), path)));
  await assertFails(getDoc(doc(db('bob'), path)));
  await assertSucceeds(updateDoc(doc(db('alice'), path), { name: 'Changed', symbol: 'apple' }));
  await assertFails(updateDoc(doc(db('alice'), path), { parentId: item }));
  await assertFails(updateDoc(doc(db('alice'), path), { rank: 'species' }));
  await assertFails(updateDoc(doc(db('bob'), path), { name: 'Stolen' }));
  await assertFails(deleteDoc(doc(db('alice'), path)));
});

test('metadata edits and archive preserve identity, position and planting date', async () => {
  await assertSucceeds(updateDoc(doc(db('alice'), itemPath), { name: 'Apple 12', rootstock: 'M.111', nursery: 'Local', notes: 'South slope', status: 'archived' }));
  await assertFails(updateDoc(doc(db('bob'), itemPath), { name: 'Stolen' }));
  await assertFails(updateDoc(doc(db(), itemPath), { status: 'active' }));
  for (const change of [{ taxonId: item }, { location: new GeoPoint(52, 2) }, { plantedOn: '2022-04-10' }, { accuracyMeters: 5 }]) {
    await assertSucceeds(updateDoc(doc(db('alice'), itemPath), change));
  }
  for (const change of [{ status: 'unknown' }, { notes: 'x'.repeat(10001) }]) {
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
  await assertFails(deleteDoc(doc(db('bob'), path)));
  await assertSucceeds(setDoc(doc(db('alice'), `${propertyPath}/tasks/${item}`), { ...task, itemId: null, dueDate: null }));
});
test('explicit phenology and lifecycle activities can be corrected', async () => {
  const { harvest: ignored, ...base } = harvest;
  let index = 10;
  for (const type of ['budBreak', 'firstBloom', 'fullBloom', 'petalFall', 'fruitSet', 'pest', 'disease', 'damage', 'harvestStart', 'harvestEnd', 'died', 'observation']) {
    const id = `00000000-0000-4000-8000-${(++index).toString().padStart(12, '0')}`;
    await assertSucceeds(setDoc(doc(db('alice'), `${itemPath}/events/${id}`), { ...base, type }));
    await assertSucceeds(updateDoc(doc(db('alice'), `${itemPath}/events/${id}`), { notes: 'Overwrite' }));
  }
});

const sectionId = '00000000-0000-4000-8000-000000000004';
const rowId = '00000000-0000-4000-8000-000000000005';
const cropId = '00000000-0000-4000-8000-000000000006';
const harvestId = '00000000-0000-4000-8000-000000000007';
const sectionPath = `${propertyPath}/sections/${sectionId}`;
const sectionData = { schemaVersion: 1, name: 'Garlic bed', kind: 'area', parentId: null, notes: '', createdAt: now, vertices: [new GeoPoint(51,1), new GeoPoint(51.001,1), new GeoPoint(51.001,1.001)] };
const cropData = { schemaVersion: 1, sectionId, taxonId: taxon, label: 'German Extra Hardy', season: '2026', notes: '', plantedOn: '2026-01-01', harvestedOn: null, status: 'growing', createdAt: now };
test('sections enforce ownership, parent scope and shape schema without destructive mutation', async () => {
  for (const uid of ['bob', undefined]) await assertFails(setDoc(doc(db(uid), sectionPath), sectionData));
  for (const change of [{ vertices: [new GeoPoint(51,1)] }, { vertices: ['bad', 'bad', 'bad'] }, { parentId: sectionId }, { parentId: item }, { kind: 'unknown' }, { vertices: Array(41).fill(new GeoPoint(51,1)) }]) {
    await assertFails(setDoc(doc(db('alice'), sectionPath), { ...sectionData, ...change }));
  }
  await assertSucceeds(setDoc(doc(db('alice'), sectionPath), sectionData));
  await assertSucceeds(setDoc(doc(db('alice'), `${propertyPath}/sections/${rowId}`), { ...sectionData, kind: 'row', name: 'Garlic row A', parentId: sectionId, vertices: sectionData.vertices.slice(0,2) }));
  await assertFails(setDoc(doc(db('alice'), `${propertyPath}/sections/${cropId}`), { ...sectionData, parentId: rowId }));
  await assertFails(updateDoc(doc(db('alice'), sectionPath), { parentId: rowId }));
  await assertFails(updateDoc(doc(db('alice'), sectionPath), { kind: 'row' }));
  await assertSucceeds(updateDoc(doc(db('alice'), sectionPath), { name: 'Garlic bed north' }));
  for (const uid of ['bob', undefined]) await assertFails(getDoc(doc(db(uid), sectionPath)));
  await assertFails(deleteDoc(doc(db('bob'), sectionPath)));
});
test('plants can move between same-property sections but cannot point at an unavailable section', async () => {
  await setDoc(doc(db('alice'), sectionPath), sectionData);
  await assertSucceeds(updateDoc(doc(db('alice'), itemPath), { sectionId }));
  await assertFails(updateDoc(doc(db('alice'), itemPath), { sectionId: rowId }));
  await assertSucceeds(updateDoc(doc(db('alice'), itemPath), { sectionId: null }));
});
test('seasonal crops retain immutable history and validate harvest records', async () => {
  await setDoc(doc(db('alice'), sectionPath), sectionData);
  const path = `${propertyPath}/crops/${cropId}`;
  await assertFails(setDoc(doc(db('bob'), path), cropData));
  await assertFails(setDoc(doc(db('alice'), path), { ...cropData, sectionId: rowId }));
  await assertSucceeds(setDoc(doc(db('alice'), path), cropData));
  await assertFails(updateDoc(doc(db('alice'), path), { label: 'Overwrite old variety' }));
  await assertFails(updateDoc(doc(db('alice'), path), { season: '2027' }));
  await assertFails(updateDoc(doc(db('alice'), path), { sectionId: rowId }));
  await assertSucceeds(updateDoc(doc(db('alice'), path), { status: 'harvested', harvestedOn: '2026-07-10' }));
  await assertSucceeds(updateDoc(doc(db('alice'), path), { status: 'ended' }));
  await assertFails(updateDoc(doc(db('alice'), path), { status: 'growing' }));
  await assertFails(deleteDoc(doc(db('bob'), path)));
  await assertFails(getDoc(doc(db('bob'), path)));
  const harvestPath = `${propertyPath}/cropHarvests/${harvestId}`;
  const data = { schemaVersion: 1, cropId, activityDate: '2026-07-10', notes: '', recordedAt: now, harvest: { quantity: 13.1, unit: 'lb' } };
  await assertFails(setDoc(doc(db('bob'), harvestPath), data));
  await assertFails(setDoc(doc(db('alice'), harvestPath), { ...data, cropId: rowId }));
  await assertFails(setDoc(doc(db('alice'), harvestPath), { ...data, harvest: { quantity: -1, unit: 'kg' } }));
  await assertSucceeds(setDoc(doc(db('alice'), harvestPath), data));
  await assertFails(updateDoc(doc(db('alice'), harvestPath), { notes: 'Overwrite' }));
  await assertFails(deleteDoc(doc(db('bob'), harvestPath)));
  await assertFails(getDoc(doc(db('bob'), harvestPath)));
});
test('group checklist batches exceed 20 members with independent immutable targets and dated completion', async () => {
  const store = db('alice');
  await env.withSecurityRulesDisabled(async (context) => {
    const seed = writeBatch(context.firestore());
    for (let i=100;i<125;i++) { const id = `00000000-0000-4000-8000-${i.toString().padStart(12,'0')}`; seed.set(doc(context.firestore(), `${propertyPath}/items/${id}`), plant); }
    await seed.commit();
  });
  const batch = writeBatch(store);
  const groupId = '00000000-0000-4000-8000-000000000008';
  const task = { schemaVersion: 1, title: 'Prune apples', notes: '', itemId: item, dueDate: null, status: 'open', createdAt: now, groupId, groupScope: 'Apple', completedOn: null };
  for (let i=100;i<125;i++) {
    const id = `00000000-0000-4000-8000-${i.toString().padStart(12,'0')}`;
    batch.set(doc(store, `${propertyPath}/tasks/${id}`), { ...task, itemId: id });
  }
  await assertSucceeds(batch.commit());
  const path = `${propertyPath}/tasks/00000000-0000-4000-8000-000000000100`;
  await assertSucceeds(updateDoc(doc(store,path), { status: 'completed', completedOn: '2026-10-16' }));
  await assertFails(updateDoc(doc(store,path), { groupId: item }));
  await assertFails(updateDoc(doc(store,path), { itemId: event }));
  await assertFails(updateDoc(doc(store,path), { status: 'skipped' }));
  await assertSucceeds(updateDoc(doc(store,path), { status: 'skipped', completedOn: null }));
  await assertFails(getDoc(doc(db('bob'), path)));
});
test('section and crop tasks require same-property targets', async () => {
  await setDoc(doc(db('alice'), sectionPath), sectionData);
  await setDoc(doc(db('alice'), `${propertyPath}/crops/${cropId}`), cropData);
  const path = `${propertyPath}/tasks/${harvestId}`;
  const task = { schemaVersion: 1, title: 'Water', notes: '', itemId: null, dueDate: null, status: 'open', createdAt: now, completedOn: null };
  await assertFails(setDoc(doc(db('alice'),path), {...task, sectionId: rowId}));
  await assertFails(setDoc(doc(db('alice'),path), {...task, sectionId, cropId}));
  await assertSucceeds(setDoc(doc(db('alice'),path), {...task, sectionId}));
  await assertSucceeds(setDoc(doc(db('alice'),`${propertyPath}/tasks/${cropId}`), {...task, cropId}));
});
test('section and crop group members complete independently and retain private scope', async () => {
  await setDoc(doc(db('alice'), sectionPath), sectionData);
  await setDoc(doc(db('alice'), `${propertyPath}/crops/${cropId}`), cropData);
  const base = { schemaVersion: 1, title: 'Harvest garlic bed', notes: '', itemId: null, dueDate: null, status: 'open', createdAt: now, groupId: event, groupScope: 'Garlic bed', completedOn: null };
  const rowTask = `${propertyPath}/tasks/${sectionId}`, cropTask = `${propertyPath}/tasks/${cropId}`;
  await assertSucceeds(setDoc(doc(db('alice'),rowTask), {...base, sectionId}));
  await assertSucceeds(setDoc(doc(db('alice'),cropTask), {...base, cropId}));
  await assertSucceeds(updateDoc(doc(db('alice'),rowTask), {status:'completed', completedOn:'2026-10-16'}));
  await assertFails(updateDoc(doc(db('bob'),cropTask), {status:'completed', completedOn:'2026-10-16'}));
  await assertFails(updateDoc(doc(db('alice'),rowTask), {sectionId:rowId}));
  await assertFails(setDoc(doc(db('alice'),`${propertyPath}/tasks/${harvestId}`), base));
});

test('multiple orchards remain owner scoped and records stay under their orchard', async () => {
  const second = '00000000-0000-4000-8000-000000000090';
  const foreign = '00000000-0000-4000-8000-000000000091';
  const secondPath = `properties/${second}`;
  const foreignPath = `properties/${foreign}`;
  await assertSucceeds(setDoc(doc(db('alice'), secondPath), { schemaVersion: 1, ownerId: 'alice', name: 'North orchard', createdAt: now }));
  await assertSucceeds(setDoc(doc(db('bob'), foreignPath), { schemaVersion: 1, ownerId: 'bob', name: 'Private orchard', createdAt: now }));
  await assertSucceeds(setDoc(doc(db('alice'), `${secondPath}/items/${item}`), { ...plant, name: 'North apple' }));
  const owned = await assertSucceeds(getDocs(query(collection(db('alice'), 'properties'), where('ownerId', '==', 'alice'))));
  if (owned.size !== 2) throw new Error('Owner query must return only the two owned orchards');
  const firstPlant = await assertSucceeds(getDoc(doc(db('alice'), itemPath)));
  const secondPlant = await assertSucceeds(getDoc(doc(db('alice'), `${secondPath}/items/${item}`)));
  if (firstPlant.data().name === secondPlant.data().name) throw new Error('Records at different orchard paths must remain independent');
  await assertFails(getDoc(doc(db('alice'), foreignPath)));
  await assertFails(getDocs(collection(db('bob'), `${secondPath}/items`)));
  await assertFails(setDoc(doc(db('alice'), `${foreignPath}/items/${event}`), plant));
});

test('owner renames orchard and styles Areas, but cannot alter orchard identity', async () => {
  await assertSucceeds(updateDoc(doc(db('alice'), propertyPath), {name:'South orchard'}));
  await assertFails(updateDoc(doc(db('bob'), propertyPath), {name:'Stolen'}));
  await assertFails(updateDoc(doc(db('alice'), propertyPath), {createdAt:Timestamp.fromMillis(0)}));
  await assertSucceeds(setDoc(doc(db('alice'),sectionPath), {...sectionData,color:0xff123456,symbol:'berry'}));
  await assertSucceeds(updateDoc(doc(db('alice'),sectionPath), {symbol:null,color:0xff654321}));
  await assertFails(updateDoc(doc(db('alice'),sectionPath), {color:-1}));
  await assertSucceeds(deleteDoc(doc(db('alice'),sectionPath)));
});
test('legacy Bed migrates in place to Area with references preserved', async () => {
  await env.withSecurityRulesDisabled(async context => setDoc(doc(context.firestore(),sectionPath),{...sectionData,kind:'bed'}));
  await assertSucceeds(updateDoc(doc(db('alice'),sectionPath),{kind:'area',color:0xff123456,symbol:'tree'}));
  await assertSucceeds(updateDoc(doc(db('alice'),itemPath),{sectionId,rowOrder:2}));
  await assertFails(updateDoc(doc(db('alice'),itemPath),{rowOrder:-1}));
});
test('zero-match recurring plans and UUID5 linked task activities remain owner scoped', async () => {
  const store=db('alice');
  const planPath=`${propertyPath}/taskPlans/${rowId}`;
  const plan={schemaVersion:1,title:'Prune apples',target:'plants',taxonId:taxon,repeat:'yearly',dueDate:'2027-01-31',createdAt:now,notes:'',eventType:'pruning'};
  await assertFails(setDoc(doc(db('bob'),planPath),plan));
  await assertSucceeds(setDoc(doc(store,planPath),plan));
  const taskId='00000000-0000-5000-8000-000000000020';
  const path=`${propertyPath}/tasks/${taskId}`;
  const task={schemaVersion:1,title:'Prune apples',itemId:item,dueDate:'2027-01-31',status:'open',createdAt:now,notes:'',planId:rowId,groupId:rowId,groupScope:'plants',occurrenceOn:'2027-01-31',eventType:'pruning'};
  await assertSucceeds(setDoc(doc(store,path),task));
  const linkedPath=`${itemPath}/events/00000000-0000-5000-8000-000000000021`;
  const {harvest: ignored,...base}=harvest;
  const batch=writeBatch(store);
  batch.update(doc(store,path),{status:'completed',completedOn:'2027-01-31'});
  batch.set(doc(store,linkedPath),{...base,type:'pruning',taskId});
  await assertSucceeds(batch.commit());
  await assertFails(updateDoc(doc(store,linkedPath),{taskId:rowId}));
  const reopen=writeBatch(store);
  reopen.update(doc(store,path),{status:'open',completedOn:null});
  reopen.delete(doc(store,linkedPath));
  await assertSucceeds(reopen.commit());
  await assertFails(deleteDoc(doc(db('bob'),planPath)));
  await assertSucceeds(deleteDoc(doc(store,path)));
  await assertSucceeds(deleteDoc(doc(store,planPath)));
});

test('icon assets and references are bounded and owner scoped', async () => {
  const iconPath = `${propertyPath}/icons/${event}`;
  const icon = { schemaVersion: 1, name: 'Pear icon', png: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=' };
  await assertFails(setDoc(doc(db('bob'), iconPath), icon));
  await assertFails(setDoc(doc(db(), iconPath), icon));
  await assertFails(setDoc(doc(db('alice'), iconPath), { ...icon, png: 'x'.repeat(50000) }));
  await assertFails(setDoc(doc(db('alice'), iconPath), { ...icon, extra: true }));
  await assertSucceeds(setDoc(doc(db('alice'), iconPath), icon));
  await assertSucceeds(getDoc(doc(db('alice'), iconPath)));
  await assertFails(getDoc(doc(db('bob'), iconPath)));
  await assertFails(updateDoc(doc(db('alice'), iconPath), { png: 'iVBORw0KGgoChanged' }));
  const option = { schemaVersion: 1, name: 'New pear', rank: 'species', parentId: taxon, symbol: 'pear', customIconId: event, iconOverride: true };
  await assertSucceeds(setDoc(doc(db('alice'), `${propertyPath}/taxa/${item}`), option));
  await assertFails(updateDoc(doc(db('alice'), `${propertyPath}/taxa/${item}`), { customIconId: property }));
  await assertFails(deleteDoc(doc(db('alice'), iconPath)));
});
