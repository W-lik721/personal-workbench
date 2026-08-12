// 云同步服务：通过 GitHub API 把本地数据备份到仓库（换机/多设备不丢数据）
// 备份文件 app-data.json 独立于网页版的 data.json，互不干扰
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'core.dart';

class Sync {
  static const _path = 'app-data.json';

  // 上传备份：本地全部数据 → 仓库 app-data.json（存在则更新）
  static Future<void> upload(String token, String repo) async {
    final body = jsonEncode(Store.exportAll());
    final content = base64Encode(utf8.encode(body));
    final uri = _uri(repo);
    // 先查文件 sha（已存在则更新需带 sha）
    String? sha;
    final r0 = await http.get(uri, headers: _h(token)).timeout(const Duration(seconds: 20));
    if (r0.statusCode == 200) {
      final j = jsonDecode(utf8.decode(r0.bodyBytes)) as Map<String, dynamic>;
      sha = j['sha'] as String?;
    } else if (r0.statusCode != 404) {
      throw Exception('云端查询失败 HTTP ${r0.statusCode}');
    }
    final resp = await http.put(
      uri,
      headers: {..._h(token), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'message': 'WorkBench App 云备份 ${DateTime.now().toIso8601String()}',
        'content': content,
        if (sha != null) 'sha': sha,
      }),
    ).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      final err = utf8.decode(resp.bodyBytes);
      throw Exception('上传失败 HTTP ${resp.statusCode}：${err.length > 160 ? err.substring(0, 160) : err}');
    }
  }

  // 下载备份：仓库 app-data.json → 解析为本地可导入的数据结构
  static Future<Map<String, dynamic>> download(String token, String repo) async {
    final r = await http.get(_uri(repo), headers: _h(token)).timeout(const Duration(seconds: 20));
    if (r.statusCode == 404) throw Exception('云端还没有备份，请先在其他设备点「上传备份」');
    if (r.statusCode != 200) throw Exception('下载失败 HTTP ${r.statusCode}');
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final content = base64Decode((j['content'] as String).replaceAll('\n', ''));
    return jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
  }

  static Uri _uri(String repo) => Uri.parse('https://api.github.com/repos/$repo/contents/$_path');
  static Map<String, String> _h(String token) => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'lite-workbench',
      };
}
