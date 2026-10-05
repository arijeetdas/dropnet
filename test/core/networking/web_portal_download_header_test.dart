import 'dart:convert';
import 'dart:io';

import 'package:dropnet/core/networking/web_portal_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

void main() {
  // macOS (13+) puts U+202F NARROW NO-BREAK SPACE before AM/PM in screenshot
  // and screen recording names.
  const macScreenshot = 'Screenshot 2026-10-05 at 10.15.32 AM.png';

  // The old portal header: dart:io refuses to write it, so shelf fails while
  // writing the response and the browser's download never completes.
  test('raw non-ASCII filename is rejected by dart:io', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      expect(
        () => request.response.headers.set('content-disposition', 'attachment; filename="$macScreenshot"'),
        throwsFormatException,
      );
      request.response.close();
    });

    final client = HttpClient();
    addTearDown(client.close);
    await (await client.get('127.0.0.1', server.port, '/')).close();
  });

  test('contentDisposition is ASCII and survives a real response', () async {
    final value = WebPortalKit.contentDisposition(macScreenshot);
    expect(value.codeUnits.every((c) => c >= 0x20 && c < 0x7F), isTrue);
    expect(value, contains('filename="Screenshot 2026-10-05 at 10.15.32_AM.png"'));
    expect(value, contains("filename*=UTF-8''Screenshot%202026-10-05%20at%2010.15.32%E2%80%AFAM.png"));

    final server = await shelf_io.serve(
      (Request _) => Response.ok('x', headers: {'content-disposition': value}),
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));

    final client = HttpClient();
    addTearDown(client.close);
    final response = await (await client.get('127.0.0.1', server.port, '/')).close();
    expect(response.statusCode, 200);
    expect(await response.transform(utf8.decoder).join(), 'x');
  });

  test('contentDisposition escapes quotes, backslashes and emoji', () {
    final value = WebPortalKit.contentDisposition('a"b\\c 😀.jpg');
    expect(value, startsWith('attachment; filename="a_b_c _.jpg"; '));
    expect(value, endsWith("filename*=UTF-8''a%22b%5Cc%20%F0%9F%98%80.jpg"));
  });
}
