import { NextResponse } from 'next/server';
import nodemailer from 'nodemailer';

export async function POST(request: Request) {
  try {
    const body = await request.json();
    const { 
      toEmail, 
      recipientName, 
      passcode, 
      latitude, 
      longitude, 
      altitude, 
      situation, 
      targetText, 
      batteryLevel 
    } = body;

    // ユーザー自身の普段のGmailアカウント情報
    const gmailUser = process.env.GMAIL_USER;
    const gmailAppPassword = process.env.GMAIL_APP_PASSWORD;

    const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || 'https://rescuepov-yamachoku-ai.vercel.app';
    const secureAccessUrl = `${siteUrl}/?passcode=${passcode}`;

    const situationTitle = situation === 'collision' ? '🚨 自動車事故・滑落の衝撃検知' :
                           situation === 'mountain_isolated' ? '⛰ 山岳遭難・孤立の検知' : '🚨 緊急SOS要請';

    const googleMapsUrl = (latitude && longitude) ? `https://www.google.com/maps?q=${latitude},${longitude}` : '#';

    // メールHTML本文（Googleメールから直接送信）
    const emailHtml = `
      <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #000; color: #fff; padding: 28px; border-radius: 16px; max-width: 600px; margin: 0 auto; border: 1px solid #333;">
        <div style="text-align: center; padding-bottom: 20px; border-bottom: 1px solid #222;">
          <h1 style="color: #ef4444; font-size: 22px; margin: 0; letter-spacing: 1px;">【緊急SOS救援要請】</h1>
          <p style="color: #888; font-size: 12px; margin-top: 6px;">RescuePOV Cloud 緊急救難警報システム</p>
        </div>

        <div style="padding: 24px 0;">
          <p style="font-size: 15px; line-height: 1.6; color: #ddd;">
            <strong>${recipientName || 'ご家族・緊急連絡先'} 様</strong><br><br>
            登録された端末から緊急救難信号が発信されました。<br>
            第三者への位置情報漏洩を防ぐため、<strong>ワンタイム・セキュリティパスコード</strong>を発行しました。以下の専用ボタンよりリアルタイム救助管制画面へ安全にアクセスしてください。
          </p>

          <div style="text-align: center; margin: 26px 0;">
            <a href="${secureAccessUrl}" style="background: linear-gradient(135deg, #ef4444, #dc2626); color: #ffffff; text-decoration: none; padding: 14px 30px; border-radius: 12px; font-weight: bold; font-size: 15px; display: inline-block; box-shadow: 0 4px 20px rgba(239, 68, 68, 0.4);">
              📍 リアルタイム現在地・管制画面を開く
            </a>
          </div>

          <div style="background: rgba(255, 255, 255, 0.05); padding: 16px; border-radius: 12px; border: 1px solid #333; margin-bottom: 20px;">
            <div style="font-size: 12px; color: #888;">🔐 暗号化ワンタイム・パスコード（手動入力用）</div>
            <div style="font-size: 26px; font-family: monospace; font-weight: bold; color: #38bdf8; letter-spacing: 4px; margin-top: 4px;">
              ${passcode}
            </div>
            <div style="font-size: 11px; color: #666; margin-top: 4px;">※このパスコードをお持ちの方のみが地図や被災状況を閲覧できます。</div>
          </div>

          <div style="background: #111; padding: 16px; border-radius: 12px; border: 1px solid #222;">
            <h3 style="margin: 0 0 12px 0; font-size: 13px; color: #bbb;">📋 端末から送信された被災ステータス</h3>
            <ul style="margin: 0; padding-left: 20px; font-size: 13px; color: #aaa; line-height: 1.8;">
              <li><strong>推定状況:</strong> <span style="color: #f97316;">${situationTitle}</span></li>
              <li><strong>現在地:</strong> 北緯 ${latitude?.toFixed(5) ?? '計測中'}, 東経 ${longitude?.toFixed(5) ?? '計測中'} (<a href="${googleMapsUrl}" style="color: #38bdf8;">Googleマップで開く</a>)</li>
              <li><strong>標高:</strong> 約 ${altitude ? Math.round(altitude) : 850} m</li>
              <li><strong>空間残像文字:</strong> <span style="color: #ef4444; font-weight: bold;">${targetText || 'HELP'}</span> (最大光量照射中)</li>
              <li><strong>バッテリー残量:</strong> ${batteryLevel ?? 85}%</li>
            </ul>
          </div>
        </div>

        <div style="text-align: center; border-top: 1px solid #222; padding-top: 16px; color: #555; font-size: 11px;">
          本通知はご本人のGoogleアカウント（${gmailUser || 'Gmail'}）より自動配信されています。
        </div>
      </div>
    `;

    // ユーザーのGmailアカウントでSMTP直接送信
    if (gmailUser && gmailAppPassword) {
      const transporter = nodemailer.createTransport({
        service: 'gmail',
        auth: {
          user: gmailUser,
          pass: gmailAppPassword
        }
      });

      const info = await transporter.sendMail({
        from: `"RescuePOV 緊急通知" <${gmailUser}>`,
        to: toEmail || gmailUser,
        subject: `【緊急SOS】救援要請が発生しました（パスコード: ${passcode}）`,
        html: emailHtml
      });

      return NextResponse.json({ 
        success: true, 
        messageId: info.messageId, 
        accessUrl: secureAccessUrl,
        sentFrom: gmailUser
      });
    } else {
      // Gmail設定がまだない場合はシミュレーションモードとして安全に処理
      console.log(`[RescuePOV Gmail Simulation] From: ${gmailUser || 'none'}, To: ${toEmail}, Passcode: ${passcode}`);
      return NextResponse.json({ 
        success: true, 
        isSimulation: true,
        message: 'Gmailのアプリパスワードが設定されると、あなたのGmailアドレスから直接送信されます。（現在はシミュレーションモード）',
        accessUrl: secureAccessUrl,
        passcode: passcode
      });
    }

  } catch (error: any) {
    return NextResponse.json({ success: false, error: error.message }, { status: 500 });
  }
}
