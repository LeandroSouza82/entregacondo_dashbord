import React from 'react';

interface EntregaCondoLogoProps {
  /** Altura em pixels; a largura acompanha a proporção do vetor. */
  height?: number;
  wordmarkColor?: string;
  subtitle?: string;
  className?: string;
}

const FONT_STACK = '"Plus Jakarta Sans", system-ui, -apple-system, "Segoe UI", sans-serif';

/**
 * Marca vetorial "EntregaCondo": ícone logístico (caixa isométrica + rota pontilhada)
 * integrado ao wordmark tipográfico. 100% SVG, escala sem perda de nitidez.
 */
export const EntregaCondoLogo: React.FC<EntregaCondoLogoProps> = ({
  height = 44,
  wordmarkColor = '#F1F5F9',
  subtitle,
  className = '',
}) => {
  const viewBoxWidth = 196;
  const viewBoxHeight = 44;

  return (
    <svg
      role="img"
      aria-label="EntregaCondo"
      viewBox={`0 0 ${viewBoxWidth} ${viewBoxHeight}`}
      height={height}
      width={(height * viewBoxWidth) / viewBoxHeight}
      className={`select-none flex-shrink-0 ${className}`}
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <defs>
        <linearGradient id="ec-logo-tile" x1="0" y1="0" x2="44" y2="44" gradientUnits="userSpaceOnUse">
          <stop offset="0" stopColor="#FB923C" />
          <stop offset="1" stopColor="#C2410C" />
        </linearGradient>
      </defs>

      {/* Ícone: tile terracota */}
      <rect width="44" height="44" rx="12" fill="url(#ec-logo-tile)" />
      <rect x="0.5" y="0.5" width="43" height="43" rx="11.5" stroke="#FFFFFF" strokeOpacity="0.18" />

      {/* Caixa isométrica (3 faces) */}
      <path d="M22 9.5 31.5 15 22 20.5 12.5 15Z" fill="#FFFFFF" />
      <path d="M12.5 15 22 20.5V32L12.5 26.5Z" fill="#FFFFFF" fillOpacity="0.55" />
      <path d="M31.5 15 22 20.5V32L31.5 26.5Z" fill="#FFFFFF" fillOpacity="0.78" />

      {/* Fita da embalagem */}
      <path d="M17.2 12.3 26.8 17.8" stroke="#C2410C" strokeOpacity="0.55" strokeWidth="1.6" strokeLinecap="round" />

      {/* Rota pontilhada com ponto de destino */}
      <path
        d="M6.5 36.5C12 39.5 20 39.5 26 36.5S35 33 37.5 35.5"
        stroke="#FFFFFF"
        strokeOpacity="0.85"
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeDasharray="0.1 3.2"
      />
      <circle cx="37.8" cy="35.6" r="2" fill="#0F1B2D" />
      <circle cx="37.8" cy="35.6" r="0.8" fill="#FFFFFF" />

      {/* Wordmark */}
      <text
        x="56"
        y={subtitle ? 24 : 29}
        fontFamily={FONT_STACK}
        fontSize="21"
        fontWeight="800"
        letterSpacing="-0.5"
        textLength="134"
        lengthAdjust="spacingAndGlyphs"
        fill={wordmarkColor}
      >
        Entrega
        <tspan fill="#FB923C" fontWeight="800">
          Condo
        </tspan>
      </text>

      {subtitle && (
        <text
          x="56.5"
          y="38"
          fontFamily={FONT_STACK}
          fontSize="8.5"
          fontWeight="600"
          letterSpacing="1.8"
          fill="#64748B"
        >
          {subtitle.toUpperCase()}
        </text>
      )}
    </svg>
  );
};
