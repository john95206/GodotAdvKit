/**
 * ADV Kit — スプレッドシート → シナリオ JSON（仕様書 §6.2 / §6.3）
 *
 * スプレッドシートに紐づけた Apps Script プロジェクトへ貼り、
 * 「デプロイ > 新しいデプロイ > ウェブアプリ」で公開する。
 * アクセスできるユーザーは「全員」。認証は URL の秘匿のみ（U-05）。
 *
 * 前提:
 *   - シートは characters / topics / steps の 3 つ
 *   - 1 行目がヘッダ行。列順には依存しない（列名で引く）
 *   - 空セルは「未指定」。"" と null を区別しない
 *
 * 出力しないもの（Godot 側の責務。仕様書 §4.8 / §6.1）:
 *   - 畳み込み（parallel 演出 / option 行）… steps は flat のまま返す
 *   - params の型変換 … すべて文字列のまま返す
 *   - 参照整合性の検証 … AdvScenarioValidator が行う
 *
 * 書き込み系（doPost）は足さないこと。足すなら U-05 の判断をやり直す。
 */

var SCHEMA_VERSION = 1;

var SHEET_CHARACTERS = 'characters';
var SHEET_TOPICS = 'topics';
var SHEET_STEPS = 'steps';

/** type ごとに拾う列。ここに無い列は無視する。 */
var STEP_COLUMNS_BY_TYPE = {
  line: ['speaker', 'expression', 'pose', 'slot', 'text', 'voice'],
  effect: ['effect_id', 'params', 'sync', 'auto_advance'],
  choice: ['prompt'],
  option: ['label', 'goto', 'flag', 'condition'],
  jump: ['goto', 'condition']
};

/** JSON 上で真偽値として出すキー。 */
var BOOLEAN_KEYS = { auto_advance: true };

/** カンマ区切りを配列にするキー。 */
var LIST_KEYS = { tags: true, poses: true, expressions: true };


function doGet(e) {
  var payload;
  try {
    payload = buildScenarioPayload();
  } catch (err) {
    payload = { schema_version: SCHEMA_VERSION, error: String(err), characters: [], topics: [] };
  }
  return ContentService
    .createTextOutput(JSON.stringify(payload))
    .setMimeType(ContentService.MimeType.JSON);
}


/** エディタから動作確認するとき用。実行ログに JSON が出る。 */
function previewScenarioJson() {
  Logger.log(JSON.stringify(buildScenarioPayload(), null, 2));
}


function buildScenarioPayload() {
  var book = SpreadsheetApp.getActiveSpreadsheet();
  var warnings = [];

  var characters = readCharacters(readRows(book, SHEET_CHARACTERS));
  var topics = readTopics(readRows(book, SHEET_TOPICS));
  attachSteps(topics, readRows(book, SHEET_STEPS), warnings);

  var payload = {
    schema_version: SCHEMA_VERSION,
    characters: characters,
    topics: topics
  };
  // content_hash は generated_at を含めずに取る。
  // 中身が変わっていないのに毎回ハッシュが変わると、インポータの差分スキップが効かない。
  payload.content_hash = computeHash(payload);
  payload.generated_at = new Date().toISOString();
  if (warnings.length > 0) {
    payload.warnings = warnings;
  }
  return payload;
}


// --- シート読み取り ----------------------------------------------------------

/** シートを「ヘッダ名 → 値」のオブジェクト配列にする。空行は落とす。 */
function readRows(book, sheetName) {
  var sheet = book.getSheetByName(sheetName);
  if (!sheet) {
    throw new Error('シート "' + sheetName + '" がありません');
  }
  var values = sheet.getDataRange().getValues();
  if (values.length < 2) {
    return [];
  }
  var headers = values[0].map(function (h) { return String(h).trim(); });
  var rows = [];
  for (var r = 1; r < values.length; r++) {
    var row = {};
    var hasValue = false;
    for (var c = 0; c < headers.length; c++) {
      if (!headers[c]) { continue; }
      var cell = values[r][c];
      row[headers[c]] = cell;
      if (String(cell).trim() !== '') { hasValue = true; }
    }
    if (hasValue) { rows.push(row); }
  }
  return rows;
}


function readCharacters(rows) {
  var characters = [];
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i];
    var id = text(row.id);
    if (!id) { continue; }
    var character = { id: id };
    assignIfPresent(character, 'display_name', row.display_name);
    assignIfPresent(character, 'name_color', row.name_color);
    assignIfPresent(character, 'portrait_dir', row.portrait_dir);
    assignIfPresent(character, 'poses', row.poses);
    assignIfPresent(character, 'expressions', row.expressions);
    assignIfPresent(character, 'default_pose', row.default_pose);
    assignIfPresent(character, 'default_expression', row.default_expression);
    characters.push(character);
  }
  return characters;
}


function readTopics(rows) {
  var topics = [];
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i];
    var id = text(row.id);
    if (!id) { continue; }
    var topic = { id: id, steps: [] };
    assignIfPresent(topic, 'title', row.title);
    assignIfPresent(topic, 'tags', row.tags);
    topics.push(topic);
  }
  return topics;
}


/**
 * steps シートの行を topic へ配る。
 * order で整列するのは Godot 側（AdvScenarioParser）だが、
 * 人が JSON を読むときのために GAS でも並べておく。
 */
function attachSteps(topics, rows, warnings) {
  var byId = {};
  for (var t = 0; t < topics.length; t++) {
    byId[topics[t].id] = topics[t];
  }
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i];
    var topicId = text(row.topic_id);
    var topic = byId[topicId];
    if (!topic) {
      warnings.push('steps 行 ' + (i + 2) + ': topic_id "' + topicId + '" が topics シートにありません');
      continue;
    }
    topic.steps.push(buildStep(row));
  }
  for (var k = 0; k < topics.length; k++) {
    topics[k].steps.sort(function (a, b) { return a.order - b.order; });
  }
}


function buildStep(row) {
  var type = text(row.type).toLowerCase();
  // order は数値のまま出す。整数として読めない値は Godot 側が missing_step_order にする
  var step = { order: toNumberOrText(row.order), type: type };
  var columns = STEP_COLUMNS_BY_TYPE[type];
  if (!columns) {
    // 未知の type もそのまま返す。unknown_step_type は Godot 側が出す
    return step;
  }
  for (var i = 0; i < columns.length; i++) {
    var key = columns[i];
    if (key === 'params') {
      var params = parseParamString(row.params);
      if (Object.keys(params).length > 0) { step.params = params; }
      continue;
    }
    assignIfPresent(step, key, row[key]);
  }
  return step;
}


// --- 値の変換 ----------------------------------------------------------------

/** 空セルはキーごと落とす（"" と null を区別しないため）。 */
function assignIfPresent(target, key, value) {
  if (BOOLEAN_KEYS[key]) {
    var boolValue = toBoolean(value);
    if (boolValue !== null) { target[key] = boolValue; }
    return;
  }
  var raw = text(value);
  if (raw === '') { return; }
  if (LIST_KEYS[key]) {
    target[key] = splitList(raw);
    return;
  }
  target[key] = raw;
}


/**
 * params セルの "key=value; key=value" を文字列辞書にする（仕様書 §6.1）。
 * [b]型変換はしない。[/b] 型は effect_id ごとのスキーマ（AdvEffectSchema）が決める。
 */
function parseParamString(value) {
  var params = {};
  var raw = text(value);
  if (raw === '') { return params; }
  var parts = raw.split(';');
  for (var i = 0; i < parts.length; i++) {
    var part = parts[i].trim();
    if (part === '') { continue; }
    var eq = part.indexOf('=');
    if (eq < 0) { continue; }
    var key = part.substring(0, eq).trim();
    if (key === '') { continue; }
    params[key] = part.substring(eq + 1).trim();
  }
  return params;
}


function splitList(raw) {
  var parts = raw.split(',');
  var list = [];
  for (var i = 0; i < parts.length; i++) {
    var part = parts[i].trim();
    if (part !== '') { list.push(part); }
  }
  return list;
}


function toBoolean(value) {
  if (typeof value === 'boolean') { return value; }
  var raw = text(value).toLowerCase();
  if (raw === '') { return null; }
  return raw === 'true' || raw === '1' || raw === 'yes' || raw === 'on';
}


function toNumberOrText(value) {
  if (typeof value === 'number') { return value; }
  var raw = text(value);
  if (raw !== '' && !isNaN(Number(raw))) { return Number(raw); }
  return raw;
}


function text(value) {
  if (value === null || value === undefined) { return ''; }
  return String(value).trim();
}


/** MD5 の 16 進表現。中身が同じなら毎回同じ値になること[b]だけ[/b]が要件。 */
function computeHash(payload) {
  var bytes = Utilities.computeDigest(
    Utilities.DigestAlgorithm.MD5, JSON.stringify(payload), Utilities.Charset.UTF_8);
  var hex = '';
  for (var i = 0; i < bytes.length; i++) {
    var byte = bytes[i] < 0 ? bytes[i] + 256 : bytes[i];
    hex += (byte < 16 ? '0' : '') + byte.toString(16);
  }
  return hex;
}
