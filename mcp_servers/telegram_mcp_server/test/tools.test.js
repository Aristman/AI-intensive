import test from 'node:test';
import assert from 'node:assert/strict';
import { createToolsHandler } from '../src/handlers/tools.js';

function makeMockClient() {
  const calls = {};
  return {
    _calls: calls,
    async getEntity(arg) {
      calls.getEntity = arg;
      return {
        id: 42,
        username: 'user42',
        firstName: 'Alice',
        lastName: 'Doe',
        className: 'User',
      };
    },
    async getMessages(chat, opts) {
      calls.getMessages = { chat, opts };
      return [
        {
          id: 1,
          message: 'hello',
          date: new Date('2024-09-01T12:34:56.000Z').toISOString(),
          senderId: 100,
          sender: { username: 'alice' },
        },
      ];
    },
    async sendMessage(chat, { message }) {
      calls.sendMessage = { chat, message };
      return { id: 777 };
    },
    async forwardMessages(toChat, ids, { fromPeer }) {
      calls.forwardMessages = { toChat, ids, fromPeer };
      return [{ id: 888 }];
    },
    async readMessages(ids) {
      calls.readMessages = { ids };
      return true;
    },
    async getDialogs() {
      calls.getDialogs = true;
      return [
        { id: 'a', title: 'Chat A', entity: { username: 'a' }, unreadCount: 2 },
        { id: 'b', title: 'Chat B', entity: { username: 'b' }, unreadCount: 3 },
      ];
    },
  };
}

function makeTools() {
  const client = makeMockClient();
  const tools = createToolsHandler(client);
  return { client, tools };
}

test('tools.list exposes only expected tg.* tools', async () => {
  const { tools } = makeTools();
  const list = await tools.list();
  const names = list.map(t => t.name).sort();
  const expected = [
    'tg.resolve_chat',
    'tg.fetch_history',
    'tg.send_message',
    'tg.forward_message',
    'tg.mark_read',
    'tg.get_unread_count',
    'tg.get_chats',
    'tg.read_messages',
  ].sort();
  assert.deepEqual(names, expected);
  assert.ok(names.every(n => n.startsWith('tg.')));
});

test('tg.resolve_chat normalizes entity info and supports chat/chatId/input', async () => {
  const { tools } = makeTools();

  const r1 = await tools.call({ name: 'tg.resolve_chat', arguments: { chat: '@user' } });
  assert.equal(r1.id, 42);
  assert.equal(r1.username, 'user42');
  assert.equal(typeof r1.title, 'string');
  assert.equal(r1.type, 'User');

  const r2 = await tools.call({ name: 'tg.resolve_chat', arguments: { chatId: '@user' } });
  assert.equal(r2.id, 42);

  const r3 = await tools.call({ name: 'tg.resolve_chat', arguments: { input: '@user' } });
  assert.equal(r3.id, 42);
});

test('tg.fetch_history maps messages and passes normalized options', async () => {
  const { tools, client } = makeTools();
  const res = await tools.call({
    name: 'tg.fetch_history',
    arguments: { chat: 'a', page_size: 50, min_id: 0, max_id: 100 },
  });
  assert.ok(Array.isArray(res.messages));
  assert.equal(res.messages[0].id, 1);
  assert.equal(res.messages[0].text, 'hello');
  assert.equal(res.messages[0].from.id, 100);
  assert.equal(res.messages[0].from.display, 'alice');

  // проверяем, что getMessages вызван с нормализованными параметрами
  assert.deepEqual(client._calls.getMessages, {
    chat: 'a',
    opts: { limit: 50, minId: 0, maxId: 100 },
  });
});

test('tg.read_messages behaves like fetch_history and supports offset', async () => {
  const { tools, client } = makeTools();
  const res = await tools.call({
    name: 'tg.read_messages',
    arguments: { chat: 'a', page_size: 10, offset: 5 },
  });
  assert.ok(Array.isArray(res.messages));
  assert.equal(client._calls.getMessages.opts.limit, 10);
  assert.equal(client._calls.getMessages.opts.offset, 5);
});

test('tg.send_message supports message/text and returns message_id', async () => {
  const { tools, client } = makeTools();
  const r1 = await tools.call({ name: 'tg.send_message', arguments: { chat: 'a', message: 'hi' } });
  assert.equal(r1.message_id, 777);
  assert.deepEqual(client._calls.sendMessage, { chat: 'a', message: 'hi' });

  const r2 = await tools.call({ name: 'tg.send_message', arguments: { chat: 'a', text: 'hello' } });
  assert.equal(r2.message_id, 777);
  assert.deepEqual(client._calls.sendMessage, { chat: 'a', message: 'hello' });
});

test('tg.forward_message normalizes keys and returns forwarded_id', async () => {
  const { tools, client } = makeTools();
  const r1 = await tools.call({
    name: 'tg.forward_message',
    arguments: { from_chat: 'a', message_id: 1, to_chat: 'b' },
  });
  assert.equal(r1.forwarded_id, 888);
  assert.deepEqual(client._calls.forwardMessages, { toChat: 'b', ids: [1], fromPeer: 'a' });

  const r2 = await tools.call({
    name: 'tg.forward_message',
    arguments: { fromChatId: 'a', messageId: 2, toChatId: 'b' },
  });
  assert.equal(r2.forwarded_id, 888);
  assert.deepEqual(client._calls.forwardMessages, { toChat: 'b', ids: [2], fromPeer: 'a' });
});

test('tg.mark_read accepts message_ids/messageIds and returns success', async () => {
  const { tools, client } = makeTools();
  const r1 = await tools.call({ name: 'tg.mark_read', arguments: { chat: 'a', message_ids: [1, 2] } });
  assert.equal(r1.success, true);
  assert.deepEqual(client._calls.readMessages, { ids: [1, 2] });

  const r2 = await tools.call({ name: 'tg.mark_read', arguments: { chat: 'a', messageIds: [3] } });
  assert.equal(r2.success, true);
  assert.deepEqual(client._calls.readMessages, { ids: [3] });
});

test('tg.get_unread_count totals unread globally and per chat', async () => {
  const { tools } = makeTools();
  const all = await tools.call({ name: 'tg.get_unread_count', arguments: {} });
  assert.equal(all.unread, 5);

  const onlyA = await tools.call({ name: 'tg.get_unread_count', arguments: { chat: 'a' } });
  assert.equal(onlyA.unread, 2);
});

test('tg.get_chats returns mapped dialogs array', async () => {
  const { tools } = makeTools();
  const chats = await tools.call({ name: 'tg.get_chats', arguments: {} });
  assert.ok(Array.isArray(chats));
  assert.equal(chats.length, 2);
  assert.deepEqual(chats[0], { id: 'a', title: 'Chat A', username: 'a', unread: 2 });
});
