'use client';

import React, { useEffect, useRef } from 'react';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';

interface RescueMapProps {
  latitude: number;
  longitude: number;
  accuracyMeters?: number;
  targetText?: string;
  situation?: string;
}

export default function RescueMap({
  latitude,
  longitude,
  accuracyMeters = 15,
  targetText = 'HELP',
  situation = 'collision'
}: RescueMapProps) {
  const mapContainerRef = useRef<HTMLDivElement>(null);
  const mapInstanceRef = useRef<L.Map | null>(null);
  const markerRef = useRef<L.Marker | null>(null);
  const circleRef = useRef<L.Circle | null>(null);

  useEffect(() => {
    if (!mapContainerRef.current) return;

    // Leafletのデフォルトアイコンパス修正
    const customIcon = L.divIcon({
      className: 'custom-rescue-pin',
      html: `
        <div style="position: relative; width: 44px; height: 44px; display: flex; align-items: center; justify-content: center;">
          <div style="position: absolute; width: 40px; height: 40px; border-radius: 50%; background: rgba(239, 68, 68, 0.4); animation: ping 1.5s cubic-bezier(0, 0, 0.2, 1) infinite;"></div>
          <div style="position: absolute; width: 22px; height: 22px; border-radius: 50%; background: #ef4444; border: 3px solid #ffffff; box-shadow: 0 0 15px rgba(239, 68, 68, 0.9);"></div>
          <div style="position: absolute; top: -20px; background: rgba(0,0,0,0.85); color: #fff; padding: 2px 6px; border-radius: 6px; font-size: 10px; font-weight: bold; border: 1px solid rgba(255,255,255,0.2); white-space: nowrap;">
            ${targetText}
          </div>
        </div>
      `,
      iconSize: [44, 44],
      iconAnchor: [22, 22]
    });

    if (!mapInstanceRef.current) {
      // マップ初期化（ダークテーマ調のOpenStreetMapタイル）
      const map = L.map(mapContainerRef.current, {
        zoomControl: false,
        attributionControl: false
      }).setView([latitude, longitude], 16);

      L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
        maxZoom: 19,
        subdomains: 'abcd'
      }).addTo(map);

      // 精度円
      const circle = L.circle([latitude, longitude], {
        radius: accuracyMeters,
        color: '#ef4444',
        fillColor: '#ef4444',
        fillOpacity: 0.15,
        weight: 1.5
      }).addTo(map);

      // マーカー
      const marker = L.marker([latitude, longitude], { icon: customIcon }).addTo(map);

      mapInstanceRef.current = map;
      markerRef.current = marker;
      circleRef.current = circle;
    } else {
      // リアルタイム座標更新時のアニメーション移動
      const map = mapInstanceRef.current;
      map.panTo([latitude, longitude], { animate: true, duration: 1.0 });

      if (markerRef.current) {
        markerRef.current.setLatLng([latitude, longitude]);
        markerRef.current.setIcon(customIcon);
      }
      if (circleRef.current) {
        circleRef.current.setLatLng([latitude, longitude]);
        circleRef.current.setRadius(accuracyMeters);
      }
    }

    return () => {
      // cleanup on unmount
    };
  }, [latitude, longitude, targetText, accuracyMeters]);

  return (
    <div className="relative w-full h-full rounded-2xl overflow-hidden border border-white/10 shadow-2xl">
      <div ref={mapContainerRef} className="w-full h-full min-h-[340px]" />
      
      {/* マップオーバーレイステータス */}
      <div className="absolute top-3 left-3 z-[1000] liquid-glass px-3 py-1.5 rounded-xl text-[11px] font-mono flex items-center gap-2 text-white">
        <span className="w-2 h-2 rounded-full bg-red-500 animate-ping" />
        リアルタイムGPS追跡中 (±{accuracyMeters}m)
      </div>

      <div className="absolute bottom-3 right-3 z-[1000] liquid-glass px-3 py-1.5 rounded-xl text-[10px] text-neutral-300 flex items-center gap-2">
        <span>© OpenStreetMap / CARTO Dark</span>
      </div>
    </div>
  );
}
