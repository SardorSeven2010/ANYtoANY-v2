import 'package:any_to_any/downloader/common.dart';
import 'package:any_to_any/downloader/hls.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final base = Uri.parse('https://cdn.example.com/video/master.m3u8?token=1');

  group('attributes', () {
    test('quoted values may contain commas', () {
      final a = parseAttributes('BANDWIDTH=800000,CODECS="avc1.4d401f,mp4a.40.2",RESOLUTION=1280x720');
      expect(a['BANDWIDTH'], '800000');
      expect(a['CODECS'], 'avc1.4d401f,mp4a.40.2');
      expect(a['RESOLUTION'], '1280x720');
    });
  });

  group('master playlist', () {
    const master = '''#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="English",DEFAULT=YES,URI="audio/en.m3u8"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="Deutsch",DEFAULT=NO,URI="audio/de.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,CODECS="avc1.4d401e",AUDIO="aud"
360p/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2800000,RESOLUTION=1920x1080,AUDIO="aud"
https://other.example.com/1080p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1400000,RESOLUTION=1280x720
720p/index.m3u8
''';

    test('lists the qualities best first and resolves relative links', () {
      final m = parseHls(master, base) as HlsMaster;
      final q = m.byQuality;
      expect(q.map((v) => v.label), ['1080p', '720p', '360p']);
      expect(q.last.url.toString(), 'https://cdn.example.com/video/360p/index.m3u8');
      expect(q.first.url.host, 'other.example.com');
      expect(q.first.bandwidth, 2800000);
    });

    test('finds the separate default audio stream of a variant', () {
      final m = parseHls(master, base) as HlsMaster;
      expect(m.audioFor(m.byQuality.first)!.toString(), 'https://cdn.example.com/video/audio/en.m3u8');
      expect(m.audioFor(m.byQuality[1]), isNull, reason: '720p has audio inside the video');
    });

    test('rejects text that is not a playlist', () {
      expect(() => parseHls('<html>nope</html>', base), throwsA(isA<DownloadException>()));
    });
  });

  group('media playlist', () {
    test('segments, durations, end list and sequence', () {
      final m = parseHls('''#EXTM3U
#EXT-X-VERSION:3
#EXT-X-MEDIA-SEQUENCE:7
#EXT-X-TARGETDURATION:10
#EXTINF:9.5,
a.ts
#EXTINF:4.25,
sub/b.ts
#EXT-X-ENDLIST
''', Uri.parse('https://x.test/path/index.m3u8')) as HlsMedia;
      expect(m.segments.length, 2);
      expect(m.segments[0].url.toString(), 'https://x.test/path/a.ts');
      expect(m.segments[1].url.toString(), 'https://x.test/path/sub/b.ts');
      expect(m.totalSeconds, closeTo(13.75, 1e-9));
      expect(m.endList, isTrue);
      expect(m.mediaSequence, 7);
      expect(m.segments[1].sequence, 8);
    });

    test('AES-128 key, init segment and byte ranges', () {
      final m = parseHls('''#EXTM3U
#EXT-X-KEY:METHOD=AES-128,URI="keys/k1.bin",IV=0x00000000000000000000000000000001
#EXT-X-MAP:URI="init.mp4",BYTERANGE="720@0"
#EXTINF:2,
#EXT-X-BYTERANGE:1000@720
big.mp4
#EXTINF:2,
#EXT-X-BYTERANGE:500
big.mp4
#EXT-X-ENDLIST
''', Uri.parse('https://x.test/v/index.m3u8')) as HlsMedia;
      expect(m.drmReason, isNull);
      expect(m.initUrl.toString(), 'https://x.test/v/init.mp4');
      expect(m.initLength, 720);
      expect(m.segments[0].key!.uri.toString(), 'https://x.test/v/keys/k1.bin');
      expect(m.segments[0].key!.iv, '0x00000000000000000000000000000001');
      expect((m.segments[0].byteOffset, m.segments[0].byteLength), (720, 1000));
      expect((m.segments[1].byteOffset, m.segments[1].byteLength), (1720, 500), reason: 'continues after the previous range');
    });

    test('DRM-protected streams are recognised and refused', () {
      for (final key in [
        '#EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://x",KEYFORMAT="com.apple.streamingkeydelivery"',
        '#EXT-X-KEY:METHOD=SAMPLE-AES-CTR,URI="data:text/plain;base64,AAAA",KEYFORMAT="urn:uuid:edef8ba9-79d6-4ace-a3c8-27dcd51d21ed"',
        '#EXT-X-KEY:METHOD=AES-128,URI="x",KEYFORMAT="com.microsoft.playready"',
      ]) {
        final m = parseHls('#EXTM3U\n$key\n#EXTINF:2,\na.ts\n#EXT-X-ENDLIST\n', base) as HlsMedia;
        expect(m.drmReason, contains('DRM'), reason: key);
      }
    });

    test('live streams (no end list) are flagged', () {
      final m = parseHls('#EXTM3U\n#EXTINF:2,\na.ts\n', base) as HlsMedia;
      expect(m.endList, isFalse);
    });
  });

  test('mux arguments allow local playlists only and copy without re-encoding', () {
    final args = hlsMuxArgs(videoPlaylist: '/w/v.m3u8', audioPlaylist: '/w/a.m3u8', outPath: '/o/out.mp4');
    expect(args, containsAllInOrder(['-protocol_whitelist', 'file,crypto,data']));
    expect(args.where((a) => a == '-i').length, 2);
    expect(args, containsAllInOrder(['-c', 'copy']));
    expect(args.last, '/o/out.mp4');
    expect(args.join(' '), isNot(contains('http')), reason: 'ffmpeg never touches the network here');
    expect(hlsMuxArgs(videoPlaylist: 'v', outPath: 'o').where((a) => a == '-i').length, 1);
  });
}
