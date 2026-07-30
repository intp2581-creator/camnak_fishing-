// 🔊 사운드 설정 다이얼로그 — 배경음/효과음 개별 on/off + 볼륨 조절
//    audioManager(fishing_logic.dart)의 설정을 즉시 반영 + localStorage 저장.
import 'package:flutter/material.dart';
import 'fishing_logic.dart';

const Color _kGold = Color(0xFFD4AF37);

Future<void> showSoundSettingsDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (dctx) => StatefulBuilder(
      builder: (dctx, setLocal) {
        Widget soundRow(
          String label,
          IconData icon,
          bool on,
          double vol,
          Future<void> Function(bool) onToggle,
          Future<void> Function(double) onVol,
        ) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, color: _kGold, size: 20),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                Switch(
                  value: on,
                  activeColor: _kGold,
                  onChanged: (v) async { await onToggle(v); setLocal(() {}); },
                ),
              ]),
              Row(children: [
                const Icon(Icons.volume_mute, color: Colors.white38, size: 18),
                Expanded(
                  child: Slider(
                    value: vol.clamp(0.0, 1.0),
                    min: 0, max: 1,
                    activeColor: _kGold,
                    inactiveColor: Colors.white24,
                    onChanged: on ? (v) async { await onVol(v); setLocal(() {}); } : null,
                  ),
                ),
                const Icon(Icons.volume_up, color: Colors.white38, size: 18),
                SizedBox(
                  width: 42,
                  child: Text('${(vol * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ),
              ]),
            ],
          );
        }

        // ⚔️ 제압 방식 선택 칩 (수동/자동/완전자동)
        Widget assistChip(int m, String label) {
          final bool sel = audioManager.combatAssist == m;
          return GestureDetector(
            onTap: () {
              audioManager.setCombatAssist(m);
              if (audioManager.sfxOn) audioManager.playSfx('sfx_click.mp3');
              setLocal(() {});
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: sel ? _kGold : Colors.white10,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: sel ? _kGold : Colors.white24, width: 1.2),
              ),
              alignment: Alignment.center,
              child: Text(label, style: TextStyle(color: sel ? Colors.black : Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          );
        }
        String assistDesc(int m) {
          switch (m) {
            case 1: return '자동: 노브를 오른쪽에 잡고만 있으면 자동 제압';
            case 2: return '완전자동: 손 안 대도 알아서 제압 (힘 부족하면 놓침)';
            default: return '수동: 물고기가 챌 때마다 놓았다 다시 당겨 제압';
          }
        }

        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: _kGold, width: 1.2)),
          title: const Text('⚙️ 설정',
              style: TextStyle(color: _kGold, fontSize: 18, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 340,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              soundRow('배경음', Icons.music_note, audioManager.bgmOn, audioManager.bgmVol,
                  audioManager.setBgmOn, audioManager.setBgmVol),
              const SizedBox(height: 10),
              soundRow('효과음', Icons.graphic_eq, audioManager.sfxOn, audioManager.sfxVol,
                  audioManager.setSfxOn, (v) async {
                await audioManager.setSfxVol(v);
                // 🔈 볼륨 감 잡으라고 조절 시 미리듣기 클릭음(효과음 켜져있을 때만)
                if (audioManager.sfxOn) audioManager.playSfx('sfx_click.mp3');
              }),
              const SizedBox(height: 14),
              const Divider(color: Colors.white24, height: 1),
              const SizedBox(height: 12),
              Row(children: const [
                Icon(Icons.sports_kabaddi, color: _kGold, size: 20),
                SizedBox(width: 8),
                Text('제압 방식', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: assistChip(0, '수동')),
                const SizedBox(width: 6),
                Expanded(child: assistChip(1, '자동')),
                const SizedBox(width: 6),
                Expanded(child: assistChip(2, '완전자동')),
              ]),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(assistDesc(audioManager.combatAssist),
                    style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4)),
              ),
            ]),
          ),
          actions: [
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _kGold, foregroundColor: Colors.black),
                onPressed: () => Navigator.pop(dctx),
                child: const Text('닫기', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        );
      },
    ),
  );
}
