import React from 'react';

interface BrandLogoProps {
  size?: 'sm' | 'md' | 'lg' | 'xl';
  showText?: boolean;
  theme?: 'light' | 'dark';
  subtitle?: string;
  className?: string;
}

export const BrandLogo: React.FC<BrandLogoProps> = ({
  size = 'md',
  showText = true,
  theme = 'light',
  subtitle,
  className = '',
}) => {
  const iconDimensions = {
    sm: 'w-7 h-7 rounded-lg',
    md: 'w-10 h-10 rounded-xl',
    lg: 'w-12 h-12 rounded-2xl',
    xl: 'w-16 h-16 rounded-3xl',
  }[size];

  const svgDimensions = {
    sm: { size: 18, stroke: 2 },
    md: { size: 24, stroke: 2.2 },
    lg: { size: 28, stroke: 2.5 },
    xl: { size: 38, stroke: 2.8 },
  }[size];

  const textSize = {
    sm: 'text-sm',
    md: 'text-lg',
    lg: 'text-xl',
    xl: 'text-2xl',
  }[size];

  const textColor = theme === 'dark' ? 'text-white' : 'text-[#0F1B2D]';

  return (
    <div className={`flex items-center gap-3 select-none ${className}`}>
      {/* Icon: Terracotta/Orange Squircle with Isometric Delivery Box */}
      <div
        className={`${iconDimensions} bg-gradient-to-br from-[#EA580C] to-[#C2410C] flex items-center justify-center shadow-lg shadow-terracotta-600/30 flex-shrink-0 ring-2 ring-terracotta-500/20`}
      >
        <svg
          width={svgDimensions.size}
          height={svgDimensions.size}
          viewBox="0 0 24 24"
          fill="none"
          stroke="white"
          strokeWidth={svgDimensions.stroke}
          strokeLinecap="round"
          strokeLinejoin="round"
        >
          {/* Isometric Package Box */}
          <path d="M12 2 L21 7 L12 12 L3 7 Z" fill="white" fillOpacity="0.2" />
          <path d="M3 7 V17 L12 22 V12 Z" fill="white" fillOpacity="0.1" />
          <path d="M21 7 V17 L12 22 V12 Z" fill="white" fillOpacity="0.3" />
          {/* Central Tape Line */}
          <line x1="7.5" y1="4.5" x2="16.5" y2="9.5" />
          <line x1="12" y1="12" x2="12" y2="22" />
        </svg>
      </div>

      {/* Brand Text */}
      {showText && (
        <div className="flex flex-col">
          <div className="flex items-center tracking-tight">
            <span className={`font-black ${textSize} ${textColor}`}>Entrega</span>
            <span
              className={`font-black ${textSize} ${
                theme === 'dark' ? 'text-terracotta-500' : 'text-[#0F1B2D]'
              }`}
            >
              Condo
            </span>
          </div>
          {subtitle && (
            <span
              className={`text-[10px] uppercase font-semibold tracking-wider ${
                theme === 'dark' ? 'text-slate-400' : 'text-slate-500'
              }`}
            >
              {subtitle}
            </span>
          )}
        </div>
      )}
    </div>
  );
};
