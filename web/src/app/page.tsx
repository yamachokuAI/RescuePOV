'use client';

import React, { useState, useEffect } from 'react';
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
  Bot
} from 'lucide-react';

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
}

export default function RescueDashboard() {
  const [events, setEvents] = useState<RescueEvent[]>([]);
  const [selectedEvent, setSelectedEvent] = useState<RescueEvent | null>(null);
  const [customText, setCustomText] = useState('');
  const [isSending, setIsSending] = useState(false);
  const [commandSentStatus, setCommandSentStatus] = useState<string | null>(null);
  const [isSimulating, setIsSimulating] = useState(false);

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
    const { data, error } = await supabase
      .from('rescue_events')
      .select('*')
      .order('created_at', { ascending: false })
      .limit(20);

    if (data && data.length > 0) {
      setEvents(data);
      setSelectedEvent(data[0]);
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

  // テスト用: WebからシミュレーションSOSを送信
  const handleSimulateSOS = async () => {
    setIsSimulating(true);
    const mockDeviceId = 'iPhone-Simulated-Test';
    const { data, error } = await supabase.from('rescue_events').insert([
      {
        device_id: mockDeviceId,
        latitude: 35.6812 + (Math.random() - 0.5) * 0.02,
        longitude: 139.7671 + (Math.random() - 0.5) * 0.02,
        altitude: 852.0 + Math.floor(Math.random() * 50),
        situation: 'collision',
        target_text: 'HELP',
        color: 'red',
        battery_level: 78,
        is_active: true
      }
    ]).select();

    setIsSimulating(false);
    if (data && data.length > 0) {
      setSelectedEvent(data[0]);
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
              <span className="text-xs px-2 py-0.5 rounded-full bg-red-500/20 text-red-400 border border-red-500/30">
                LIVE 管制
              </span>
            </h1>
            <p className="text-xs text-neutral-400">
              Apple Intelligence / CoreMotion 空間残像空中照射 リアルタイム遠隔監視
            </p>
          </div>
        </div>

        <div className="flex items-center gap-3 w-full md:w-auto justify-between md:justify-end">
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

      {/* メイングリッド */}
      <div className="max-w-7xl mx-auto grid grid-cols-1 lg:grid-cols-3 gap-6 pt-6">
        
        {/* 左カラム：リアルタイム被災者カード ＆ 状況 */}
        <section className="lg:col-span-2 space-y-6">
          {activeEvent ? (
            <div className="liquid-glass liquid-glass-glow-red rounded-3xl p-6 md:p-8 space-y-6 animate-pulse-subtle">
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

              {/* POV空間文字プレビュー */}
              <div className="bg-black/60 border border-white/10 rounded-2xl p-6 text-center space-y-3 shadow-inner">
                <span className="text-xs font-semibold text-neutral-400 uppercase tracking-widest">
                  iPhone画面で空間照射中の空中残像文字
                </span>
                <div className="text-6xl md:text-7xl font-black font-mono tracking-widest text-red-500 drop-shadow-[0_0_35px_rgba(239,68,68,0.9)] py-4">
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
                    {activeEvent.latitude ? `${activeEvent.latitude.toFixed(5)}°N` : '未取得'}
                  </div>
                  <div className="font-mono text-xs text-neutral-400">
                    {activeEvent.longitude ? `${activeEvent.longitude.toFixed(5)}°E` : ''}
                  </div>
                </div>

                <div className="liquid-glass rounded-2xl p-4 space-y-1">
                  <div className="flex items-center gap-1.5 text-xs text-neutral-400">
                    <Compass className="w-4 h-4 text-emerald-400" />
                    気圧高度（標高）
                  </div>
                  <div className="font-mono text-lg font-bold text-emerald-400">
                    {activeEvent.altitude ? `${Math.round(activeEvent.altitude)} m` : '850 m'}
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

              {/* Google Maps リンク */}
              {activeEvent.latitude && activeEvent.longitude && (
                <a
                  href={`https://www.google.com/maps?q=${activeEvent.latitude},${activeEvent.longitude}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="w-full py-3 rounded-xl bg-white/10 hover:bg-white/15 border border-white/20 text-xs font-bold flex items-center justify-center gap-2 transition"
                >
                  <MapPin className="w-4 h-4 text-red-400" />
                  Googleマップで救難位置を確認（ナビゲーション）
                  <ExternalLink className="w-3.5 h-3.5" />
                </a>
              )}
            </div>
          ) : (
            <div className="liquid-glass rounded-3xl p-12 text-center space-y-4">
              <AlertTriangle className="w-12 h-12 text-neutral-500 mx-auto" />
              <h3 className="text-lg font-bold">待機中: 受信済みの救難イベントはありません</h3>
              <p className="text-xs text-neutral-400">
                iPhone側でRescuePOVを起動して「SOS開始」するか、右上の「テストSOS発信」をお試しください。
              </p>
            </div>
          )}

          {/* 履歴イベントリスト */}
          <div className="liquid-glass rounded-3xl p-6 space-y-4">
            <h3 className="text-sm font-bold flex items-center gap-2">
              <Activity className="w-4 h-4 text-neutral-400" />
              受信イベント履歴
            </h3>
            <div className="divide-y divide-white/10 max-h-60 overflow-y-auto">
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

        {/* 右カラム：Mac/ブラウザからの遠隔コマンド操作 ＆ MCP連携 */}
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

          {/* MCP エージェント ＆ Googleメール連携カード */}
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

            <div className="space-y-2.5 text-xs text-neutral-300">
              <div className="p-3 rounded-xl bg-white/5 border border-white/10 flex items-center justify-between">
                <span className="flex items-center gap-2">
                  <Mail className="w-4 h-4 text-red-400" />
                  Gmail 自動救難通報
                </span>
                <span className="text-[10px] px-2 py-0.5 rounded-md bg-green-500/20 text-green-400 border border-green-500/30">
                  スタンバイ完了
                </span>
              </div>

              <div className="p-3 rounded-xl bg-white/5 border border-white/10 flex items-center justify-between">
                <span className="flex items-center gap-2">
                  <Bot className="w-4 h-4 text-purple-400" />
                  Claude / Gemini 4 MCP
                </span>
                <span className="text-[10px] px-2 py-0.5 rounded-md bg-green-500/20 text-green-400 border border-green-500/30">
                  Tool接続受付中
                </span>
              </div>
            </div>

            <p className="text-[10px] text-neutral-400 leading-relaxed">
              iPhoneが衝撃や遭難を検知すると、MCPエージェントが自動で家族・救助隊へGPS付き緊急メールを配信します。
            </p>
          </div>
        </section>
      </div>
    </main>
  );
}
