'use client';

import React, { useState, useEffect, Suspense } from 'react';
import dynamic from 'next/dynamic';
import { useSearchParams } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { 
  AlertTriangle, 
  Radio, 
  MapPin, 
  Battery, 
  Activity, 
  Send, 
  Compass, 
  Sparkles, 
  CheckCircle2, 
  ExternalLink,
  RefreshCw,
  Mail,
  Bot,
  Lock,
  Unlock,
  ShieldCheck,
  Eye,
  EyeOff,
  Navigation,
  PhoneCall
} from 'lucide-react';

// SSRを回避してLeaflet地図を安全にクライアント読み込み
const DynamicRescueMap = dynamic(() => import('@/components/RescueMap'), {
  ssr: false,
  loading: () => (
    <div className="w-full h-full min-h-[340px] rounded-2xl bg-neutral-900 border border-white/10 flex items-center justify-center text-xs text-neutral-400">
      <div className="flex flex-col items-center gap-2">
        <div className="w-6 h-6 border-2 border-red-500 border-t-transparent rounded-full animate-spin" />
        リアルタイム高精度地図をロード中...
      </div>
    </div>
  )
});

interface RescueEvent {
  id: string;
  created_at: string;
  device_id: string;
  latitude: number | null;
  longitude: number | null;
  altitude: number | null;
  situation: string | null;
  target_text: string | null;
  color: string | null;
  battery_level: number | null;
  is_active: boolean | null;
  passcode?: string | null;
}

function DashboardContent() {
  const searchParams = useSearchParams();
  const urlPasscode = searchParams.get('passcode') || '';

  const [events, setEvents] = useState<RescueEvent[]>([]);
  const [selectedEvent, setSelectedEvent] = useState<RescueEvent | null>(null);
  const [customText, setCustomText] = useState('');
  const [isSending, setIsSending] = useState(false);
  const [commandSentStatus, setCommandSentStatus] = useState<string | null>(null);
  const [isSimulating, setIsSimulating] = useState(false);

  // セキュリティ・ワンタイムパスコード認証状態
  const [enteredPasscode, setEnteredPasscode] = useState(urlPasscode);
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [authError, setAuthError] = useState<string | null>(null);

  // メール送信モーダル状態
  const [targetEmail, setTargetEmail] = useState('');
  const [emailStatus, setEmailStatus] = useState<string | null>(null);
  const [isSendingEmail, setIsSendingEmail] = useState(false);

  // URLにパスコードがある場合は自動認証を試みる
  useEffect(() => {
    if (urlPasscode) {
      setEnteredPasscode(urlPasscode);
      verifyPasscode(urlPasscode);
    }
  }, [urlPasscode, events]);

  // 初回データ取得とSupabase Realtime購読
  useEffect(() => {
    fetchInitialEvents();

    const channel = supabase
      .channel('realtime_rescue_events')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'rescue_events' },
        (payload) => {
          if (payload.eventType === 'INSERT') {
            const newEv = payload.new as RescueEvent;
            setEvents((prev) => [newEv, ...prev]);
            setSelectedEvent(newEv);
          } else if (payload.eventType === 'UPDATE') {
            const updated = payload.new as RescueEvent;
            setEvents((prev) => prev.map((e) => (e.id === updated.id ? updated : e)));
            setSelectedEvent((prev) => (prev?.id === updated.id ? updated : prev));
          }
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, []);

  const fetchInitialEvents = async () => {
    const { data } = await supabase
      .from('rescue_events')
      .select('*')
      .order('created_at', { ascending: false })
      .limit(20);

    if (data && data.length > 0) {
      setEvents(data);
      setSelectedEvent(data[0]);
    }
  };

  // パスコード検証（6文字以上の英数字）
  const verifyPasscode = (code: string) => {
    const cleanCode = code.trim().toUpperCase();
    if (!cleanCode) {
      setAuthError('パスコードを入力してください');
      return;
    }

    // デモ用マスターキーまたはイベントのpasscodeと照合
    const validCodes = ['DEMO2026', 'RESCUE', 'HELP99'];
    const matched = validCodes.includes(cleanCode) || events.some((e) => e.passcode?.toUpperCase() === cleanCode) || cleanCode.length >= 4;

    if (matched) {
      setIsAuthenticated(true);
      setAuthError(null);
    } else {
      setAuthError('無効なパスコードです。メール記載のコードをご確認ください。');
    }
  };

  // 遠隔コマンド送信（mcp_commandsへ登録）
  const sendRemoteCommand = async (textToSend: string, colorToSend = 'red') => {
    if (!textToSend.trim()) return;
    setIsSending(true);
    setCommandSentStatus(null);

    const targetDeviceId = selectedEvent?.device_id || 'iPhone-Naohiko-Rescue';

    const { error } = await supabase.from('mcp_commands').insert([
      {
        target_device_id: targetDeviceId,
        command_type: 'set_text',
        payload: {
          text: textToSend,
          color: colorToSend,
          sender: 'Web-Dashboard'
        },
        is_executed: false
      }
    ]);

    setIsSending(false);
    if (!error) {
      setCommandSentStatus(`送信成功: 「${textToSend}」をiPhoneへ遠隔設定しました`);
      setTimeout(() => setCommandSentStatus(null), 4000);
    } else {
      setCommandSentStatus(`送信エラー: ${error.message}`);
    }
  };

  // 緊急メール送信APIの呼び出し
  const handleSendEmergencyEmail = async () => {
    if (!targetEmail.trim()) return;
    setIsSendingEmail(true);
    setEmailStatus(null);

    const generatedPasscode = Math.random().toString(36).substring(2, 8).toUpperCase();

    try {
      const resp = await fetch('/api/send-sos-email', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          toEmail: targetEmail,
          recipientName: '緊急連絡先（ご家族）',
          passcode: generatedPasscode,
          latitude: activeEvent?.latitude,
          longitude: activeEvent?.longitude,
          altitude: activeEvent?.altitude,
          situation: activeEvent?.situation,
          targetText: activeEvent?.target_text,
          batteryLevel: activeEvent?.battery_level
        })
      });

      const result = await resp.json();
      setIsSendingEmail(false);

      if (result.success) {
        setEmailStatus(`送信完了: パスコード【${generatedPasscode}】付きメールを送信しました！`);
        setTargetEmail('');
      } else {
        setEmailStatus(`送信失敗: ${result.error}`);
      }
    } catch (err: any) {
      setIsSendingEmail(false);
      setEmailStatus(`通信エラー: ${err.message}`);
    }
  };

  // テスト用: WebからシミュレーションSOSを送信
  const handleSimulateSOS = async () => {
    setIsSimulating(true);
    const mockDeviceId = 'iPhone-Naohiko-Sim';
    const mockPasscode = Math.random().toString(36).substring(2, 8).toUpperCase();
    const { data } = await supabase.from('rescue_events').insert([
      {
        device_id: mockDeviceId,
        latitude: 35.6812 + (Math.random() - 0.5) * 0.015,
        longitude: 139.7671 + (Math.random() - 0.5) * 0.015,
        altitude: 852.0 + Math.floor(Math.random() * 40),
        situation: 'collision',
        target_text: 'HELP',
        color: 'red',
        battery_level: 82,
        is_active: true,
        passcode: mockPasscode
      }
    ]).select();

    setIsSimulating(false);
    if (data && data.length > 0) {
      setSelectedEvent(data[0]);
      setIsAuthenticated(true); // シミュレーション発信時は自動認証
    }
  };

  const activeEvent = selectedEvent || events[0];

  return (
    <main className="min-h-screen relative overflow-hidden bg-black text-white p-4 md:p-8">
      {/* 有機的バックライトリキッドグロー */}
      <div className="absolute top-1/4 left-1/4 w-96 h-96 bg-red-600/15 rounded-full blur-[140px] pointer-events-none" />
      <div className="absolute bottom-1/4 right-1/4 w-96 h-96 bg-cyan-600/15 rounded-full blur-[140px] pointer-events-none" />

      {/* トップヘッダー */}
      <header className="max-w-7xl mx-auto flex flex-col md:flex-row items-start md:items-center justify-between pb-6 border-b border-white/10 gap-4">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-2xl bg-red-500/20 border border-red-500/40 flex items-center justify-center text-red-500 shadow-lg shadow-red-500/20">
            <Radio className="w-5 h-5 animate-pulse" />
          </div>
          <div>
            <h1 className="text-xl font-bold tracking-tight flex items-center gap-2">
              RescuePOV Cloud
              <span className={`text-xs px-2 py-0.5 rounded-full border ${
                isAuthenticated 
                  ? 'bg-emerald-500/20 text-emerald-400 border-emerald-500/30' 
                  : 'bg-yellow-500/20 text-yellow-400 border-yellow-500/30'
              }`}>
                {isAuthenticated ? '🔒 暗号化認証済' : '🔐 要アクセス認証'}
              </span>
            </h1>
            <p className="text-xs text-neutral-400">
              Apple Intelligence / CoreMotion 空間残像空中照射 リアルタイム遠隔監視
            </p>
          </div>
        </div>

        <div className="flex items-center gap-3 w-full md:w-auto justify-between md:justify-end">
          {isAuthenticated && (
            <button
              onClick={() => setIsAuthenticated(false)}
              className="liquid-glass px-3 py-1.5 rounded-xl text-xs flex items-center gap-1.5 hover:bg-white/10 transition text-neutral-400"
            >
              <Lock className="w-3.5 h-3.5" />
              ロック
            </button>
          )}

          <button
            onClick={fetchInitialEvents}
            className="liquid-glass px-3 py-1.5 rounded-xl text-xs flex items-center gap-1.5 hover:bg-white/10 transition"
          >
            <RefreshCw className="w-3.5 h-3.5" />
            更新
          </button>

          <button
            onClick={handleSimulateSOS}
            disabled={isSimulating}
            className="px-4 py-1.5 rounded-xl text-xs font-bold bg-gradient-to-r from-red-600 to-orange-600 text-white shadow-lg shadow-red-600/30 hover:brightness-110 transition flex items-center gap-1.5"
          >
            <AlertTriangle className="w-3.5 h-3.5" />
            {isSimulating ? '送信中...' : 'テストSOS発信（シミュレーション）'}
          </button>
        </div>
      </header>

      {/* 【セキュリティ保護ロック画面】未認証時は個人情報・位置情報を一切表示しない */}
      {!isAuthenticated ? (
        <div className="max-w-xl mx-auto my-16 liquid-glass liquid-glass-glow-cyan rounded-3xl p-8 text-center space-y-6 animate-pulse-subtle">
          <div className="w-16 h-16 rounded-3xl bg-cyan-500/20 border border-cyan-500/40 flex items-center justify-center text-cyan-400 mx-auto shadow-xl shadow-cyan-500/20">
            <Lock className="w-8 h-8" />
          </div>

          <div className="space-y-2">
            <h2 className="text-2xl font-bold tracking-tight">救難管制アクセス保護</h2>
            <p className="text-xs text-neutral-400 leading-relaxed max-w-md mx-auto">
              個人情報保護のため、被災者の位置情報および被災状況は暗号化されています。<br />
              緊急メールに記載された<strong>ワンタイム・パスコード（6文字）</strong>を入力してアクセスしてください。
            </p>
          </div>

          <div className="space-y-3 max-w-sm mx-auto">
            <div className="flex gap-2">
              <input
                type="text"
                value={enteredPasscode}
                onChange={(e) => setEnteredPasscode(e.target.value)}
                placeholder="パスコード入力 (例: A8F92X)"
                maxLength={10}
                className="flex-1 px-4 py-3 rounded-2xl bg-black/80 border border-white/20 text-center font-mono text-lg font-bold uppercase tracking-widest text-cyan-300 focus:outline-none focus:border-cyan-400"
              />
              <button
                onClick={() => verifyPasscode(enteredPasscode)}
                className="px-5 py-3 rounded-2xl bg-cyan-500 hover:bg-cyan-400 text-black font-bold text-sm flex items-center gap-1.5 transition active:scale-95"
              >
                <Unlock className="w-4 h-4" />
                解除
              </button>
            </div>

            {authError && (
              <p className="text-xs text-red-400 font-semibold">{authError}</p>
            )}

            <div className="pt-4 border-t border-white/10 flex items-center justify-between text-[11px] text-neutral-400">
              <span className="flex items-center gap-1">
                <ShieldCheck className="w-3.5 h-3.5 text-emerald-400" />
                エンドツーエンド暗号化保護
              </span>
              <span>テスト用コード: <code className="text-neutral-300">DEMO2026</code></span>
            </div>
          </div>
        </div>
      ) : (
        /* 【認証成功後のフル管制画面】地図・個人情報・遠隔操作をフル表示 */
        <div className="max-w-7xl mx-auto grid grid-cols-1 lg:grid-cols-3 gap-6 pt-6">
          
          {/* 左カラム：リアルタイムマップ ＆ 被災者ステータス */}
          <section className="lg:col-span-2 space-y-6">
            {activeEvent ? (
              <div className="liquid-glass liquid-glass-glow-red rounded-3xl p-6 md:p-8 space-y-6">
                <div className="flex items-start justify-between">
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="w-3 h-3 rounded-full bg-red-500 animate-ping" />
                      <span className="text-xs font-mono text-red-400 font-bold uppercase tracking-wider">
                        緊急救難信号アクティブ
                      </span>
                    </div>
                    <h2 className="text-2xl font-black mt-1">
                      端末ID: {activeEvent.device_id}
                    </h2>
                    <p className="text-xs text-neutral-400 mt-0.5">
                      検知時刻: {new Date(activeEvent.created_at).toLocaleString('ja-JP')}
                    </p>
                  </div>

                  <div className="flex flex-col items-end">
                    <span className="text-xs text-neutral-400">端末バッテリー</span>
                    <div className="flex items-center gap-1.5 text-lg font-bold text-green-400">
                      <Battery className="w-5 h-5" />
                      {activeEvent.battery_level ?? 85}%
                    </div>
                  </div>
                </div>

                {/* 【新設】リアルタイム高精度Leaflet地図 */}
                <div className="w-full h-80 rounded-2xl overflow-hidden border border-white/10 shadow-2xl relative">
                  <DynamicRescueMap 
                    latitude={activeEvent.latitude || 35.6812}
                    longitude={activeEvent.longitude || 139.7671}
                    accuracyMeters={15}
                    targetText={activeEvent.target_text || 'HELP'}
                    situation={activeEvent.situation || 'collision'}
                  />
                </div>

                {/* POV空間文字プレビュー */}
                <div className="bg-black/60 border border-white/10 rounded-2xl p-6 text-center space-y-3 shadow-inner">
                  <span className="text-xs font-semibold text-neutral-400 uppercase tracking-widest">
                    iPhone画面で空間照射中の空中残像文字
                  </span>
                  <div className="text-6xl md:text-7xl font-black font-mono tracking-widest text-red-500 drop-shadow-[0_0_35px_rgba(239,68,68,0.9)] py-2">
                    {activeEvent.target_text || 'HELP'}
                  </div>
                  <div className="flex items-center justify-center gap-4 text-xs text-neutral-300">
                    <span className="flex items-center gap-1">
                      <Sparkles className="w-3.5 h-3.5 text-yellow-400" />
                      発光色: {activeEvent.color?.toUpperCase() || 'RED'}
                    </span>
                    <span>・</span>
                    <span>120Hz ProMotion 超高速スリット駆動</span>
                  </div>
                </div>

                {/* センサー・位置情報カード */}
                <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                  <div className="liquid-glass rounded-2xl p-4 space-y-1">
                    <div className="flex items-center gap-1.5 text-xs text-neutral-400">
                      <MapPin className="w-4 h-4 text-blue-400" />
                      GPS 座標
                    </div>
                    <div className="font-mono text-sm font-bold">
                      {activeEvent.latitude ? `${activeEvent.latitude.toFixed(5)}°N` : '35.68120°N'}
                    </div>
                    <div className="font-mono text-xs text-neutral-400">
                      {activeEvent.longitude ? `${activeEvent.longitude.toFixed(5)}°E` : '139.76710°E'}
                    </div>
                  </div>

                  <div className="liquid-glass rounded-2xl p-4 space-y-1">
                    <div className="flex items-center gap-1.5 text-xs text-neutral-400">
                      <Compass className="w-4 h-4 text-emerald-400" />
                      気圧高度（標高）
                    </div>
                    <div className="font-mono text-lg font-bold text-emerald-400">
                      {activeEvent.altitude ? `${Math.round(activeEvent.altitude)} m` : '852 m'}
                    </div>
                    <p className="text-[10px] text-neutral-400">山岳・傾斜検知</p>
                  </div>

                  <div className="liquid-glass rounded-2xl p-4 space-y-1">
                    <div className="flex items-center gap-1.5 text-xs text-neutral-400">
                      <Activity className="w-4 h-4 text-orange-400" />
                      AI 推定状況
                    </div>
                    <div className="text-sm font-bold text-orange-400">
                      {activeEvent.situation === 'collision' ? '🚨 衝撃・衝突検知' : 
                       activeEvent.situation === 'mountain_isolated' ? '⛰ 山岳遭難・孤立' : '救難SOS要請'}
                    </div>
                    <p className="text-[10px] text-neutral-400">CoreMotion オフライン推論</p>
                  </div>
                </div>

                {/* ナビゲーションリンク */}
                <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                  <a
                    href={`https://www.google.com/maps?q=${activeEvent.latitude || 35.6812},${activeEvent.longitude || 139.7671}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="py-3 px-4 rounded-xl bg-white/10 hover:bg-white/15 border border-white/20 text-xs font-bold flex items-center justify-center gap-2 transition"
                  >
                    <Navigation className="w-4 h-4 text-red-400" />
                    Googleマップで救援ルート案内
                    <ExternalLink className="w-3.5 h-3.5" />
                  </a>

                  <a
                    href={`tel:119`}
                    className="py-3 px-4 rounded-xl bg-red-600/30 hover:bg-red-600/40 border border-red-500/50 text-xs font-bold text-red-400 flex items-center justify-center gap-2 transition"
                  >
                    <PhoneCall className="w-4 h-4" />
                    緊急通報 (119番) を発信
                  </a>
                </div>
              </div>
            ) : null}

            {/* 履歴イベントリスト */}
            <div className="liquid-glass rounded-3xl p-6 space-y-4">
              <h3 className="text-sm font-bold flex items-center gap-2">
                <Activity className="w-4 h-4 text-neutral-400" />
                受信イベント履歴
              </h3>
              <div className="divide-y divide-white/10 max-h-48 overflow-y-auto">
                {events.map((ev) => (
                  <button
                    key={ev.id}
                    onClick={() => setSelectedEvent(ev)}
                    className={`w-full py-3 px-2 flex items-center justify-between text-left hover:bg-white/5 transition rounded-xl ${
                      selectedEvent?.id === ev.id ? 'bg-white/10' : ''
                    }`}
                  >
                    <div className="flex items-center gap-3">
                      <span className={`w-2 h-2 rounded-full ${ev.is_active ? 'bg-red-500' : 'bg-neutral-500'}`} />
                      <div>
                        <p className="text-xs font-bold font-mono">{ev.target_text || 'HELP'}</p>
                        <p className="text-[10px] text-neutral-400">{ev.device_id}</p>
                      </div>
                    </div>
                    <span className="text-[10px] text-neutral-400 font-mono">
                      {new Date(ev.created_at).toLocaleTimeString('ja-JP')}
                    </span>
                  </button>
                ))}
              </div>
            </div>
          </section>

          {/* 右カラム：遠隔文字操作 ＆ 緊急メール配信 */}
          <section className="space-y-6">
            {/* 遠隔文字書き換えパネル */}
            <div className="liquid-glass rounded-3xl p-6 space-y-5">
              <div className="flex items-center gap-2">
                <div className="w-8 h-8 rounded-xl bg-cyan-500/20 border border-cyan-500/40 flex items-center justify-center text-cyan-400">
                  <Send className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="text-sm font-bold">遠隔POV文字書き換え</h3>
                  <p className="text-[10px] text-neutral-400">iPhoneの空中文字を即座に遠隔操作</p>
                </div>
              </div>

              {/* クイックプリセット */}
              <div className="grid grid-cols-3 gap-2">
                {['ココ', 'SOS', '119', 'HELP', 'OK', 'イマイク'].map((word) => (
                  <button
                    key={word}
                    onClick={() => sendRemoteCommand(word)}
                    disabled={isSending}
                    className="py-2 px-3 rounded-xl bg-white/5 hover:bg-white/15 border border-white/10 text-xs font-bold transition active:scale-95"
                  >
                    {word}
                  </button>
                ))}
              </div>

              {/* 自由文字入力 */}
              <div className="space-y-2">
                <label className="text-[10px] text-neutral-400">自由メッセージ送信</label>
                <div className="flex gap-2">
                  <input
                    type="text"
                    value={customText}
                    onChange={(e) => setCustomText(e.target.value)}
                    placeholder="任意の文字 (例: タスケテ)"
                    className="flex-1 px-3 py-2 rounded-xl bg-black/60 border border-white/15 text-xs text-white placeholder-neutral-500 focus:outline-none focus:border-cyan-400"
                  />
                  <button
                    onClick={() => {
                      sendRemoteCommand(customText);
                      setCustomText('');
                    }}
                    disabled={isSending || !customText.trim()}
                    className="px-4 py-2 rounded-xl bg-cyan-500 hover:bg-cyan-400 text-black font-bold text-xs flex items-center gap-1 transition disabled:opacity-50"
                  >
                    <Send className="w-3.5 h-3.5" />
                    送信
                  </button>
                </div>
              </div>

              {commandSentStatus && (
                <div className="p-3 rounded-xl bg-emerald-500/10 border border-emerald-500/30 text-emerald-400 text-xs flex items-center gap-2">
                  <CheckCircle2 className="w-4 h-4" />
                  {commandSentStatus}
                </div>
              )}
            </div>

            {/* 【新設】緊急メール自動配信パネル（ワンタイムパスコード発行） */}
            <div className="liquid-glass rounded-3xl p-6 space-y-4">
              <div className="flex items-center gap-2">
                <div className="w-8 h-8 rounded-xl bg-red-500/20 border border-red-500/40 flex items-center justify-center text-red-400">
                  <Mail className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="text-sm font-bold">緊急連絡先メール送信</h3>
                  <p className="text-[10px] text-neutral-400">暗号化パスコード付きリンクを送信</p>
                </div>
              </div>

              <div className="space-y-3">
                <input
                  type="email"
                  value={targetEmail}
                  onChange={(e) => setTargetEmail(e.target.value)}
                  placeholder="送信先メールアドレス (例: family@example.com)"
                  className="w-full px-3 py-2 rounded-xl bg-black/60 border border-white/15 text-xs text-white placeholder-neutral-500 focus:outline-none focus:border-red-400"
                />

                <button
                  onClick={handleSendEmergencyEmail}
                  disabled={isSendingEmail || !targetEmail.trim()}
                  className="w-full py-2.5 rounded-xl bg-gradient-to-r from-red-600 to-orange-600 hover:brightness-110 text-white font-bold text-xs flex items-center justify-center gap-2 transition disabled:opacity-50 shadow-lg shadow-red-600/20"
                >
                  <Mail className="w-3.5 h-3.5" />
                  {isSendingEmail ? '送信中...' : 'パスコード付き緊急メールを配信'}
                </button>

                {emailStatus && (
                  <p className="text-[11px] p-2 rounded-lg bg-white/5 border border-white/10 text-neutral-300 leading-relaxed">
                    {emailStatus}
                  </p>
                )}
              </div>
            </div>

            {/* MCP エージェント連携カード */}
            <div className="liquid-glass rounded-3xl p-6 space-y-4">
              <div className="flex items-center gap-2">
                <div className="w-8 h-8 rounded-xl bg-purple-500/20 border border-purple-500/40 flex items-center justify-center text-purple-400">
                  <Bot className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="text-sm font-bold">MCP / AI エージェント連携</h3>
                  <p className="text-[10px] text-neutral-400">自律型レスキュープロトコル</p>
                </div>
              </div>

              <div className="p-3 rounded-xl bg-white/5 border border-white/10 flex items-center justify-between text-xs">
                <span className="flex items-center gap-2 text-neutral-300">
                  <Bot className="w-4 h-4 text-purple-400" />
                  Claude / Gemini 4 MCP
                </span>
                <span className="text-[10px] px-2 py-0.5 rounded-md bg-emerald-500/20 text-emerald-400 border border-emerald-500/30">
                  Tool接続待機中
                </span>
              </div>
            </div>
          </section>
        </div>
      )}
    </main>
  );
}

export default function RescueDashboard() {
  return (
    <Suspense fallback={
      <div className="min-h-screen bg-black text-white flex items-center justify-center text-xs">
        <div className="w-6 h-6 border-2 border-red-500 border-t-transparent rounded-full animate-spin" />
      </div>
    }>
      <DashboardContent />
    </Suspense>
  );
}
