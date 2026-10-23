import React from 'react';

export type TipoVeiculoIcone = 'moto' | 'carro' | 'caminhao';

export interface VehicleIconProps extends React.SVGProps<SVGSVGElement> {
  size?: number;
  className?: string;
  primaryColor?: string;
  accentColor?: string;
}

/**
 * Ícone SVG de Moto de Entrega Expressa (Design System EntregaCondo)
 * Silhueta moderna de scooter/moto street com baú térmico em terracota,
 * carenagem angulada, farol LED e rodas com aro contrastante.
 */
export const IconeMoto: React.FC<VehicleIconProps> = ({
  size = 28,
  className = '',
  primaryColor = '#0F1B2D',
  accentColor = '#EA580C',
  ...props
}) => (
  <svg
    width={size}
    height={size}
    viewBox="0 0 32 32"
    fill="none"
    xmlns="http://www.w3.org/2000/svg"
    className={className}
    {...props}
  >
    {/* Sombra de base sutil */}
    <ellipse cx="16" cy="26.5" rx="12" ry="1.5" fill={primaryColor} fillOpacity="0.18" />

    {/* Roda Traseira */}
    <circle cx="7.5" cy="22" r="4.2" fill="#1E293B" stroke={primaryColor} strokeWidth="2" />
    <circle cx="7.5" cy="22" r="1.8" fill="#E2E8F0" />

    {/* Roda Dianteira */}
    <circle cx="24.5" cy="22" r="4.2" fill="#1E293B" stroke={primaryColor} strokeWidth="2" />
    <circle cx="24.5" cy="22" r="1.8" fill="#E2E8F0" />

    {/* Para-lama Dianteiro */}
    <path
      d="M21 19C22.2 17.6 24.8 17.4 26.8 18.5"
      stroke={accentColor}
      strokeWidth="2"
      strokeLinecap="round"
    />

    {/* Chassi / Monobloco e Carenagem */}
    <path
      d="M7.5 22L11.5 16.5H16.5L18.5 20.5H13.5L7.5 22Z"
      fill={primaryColor}
      fillOpacity="0.25"
    />
    <path
      d="M7.5 22L12 16.2H17.2L19 20.5H21.2L23.2 12.2L20.5 10.5"
      stroke={primaryColor}
      strokeWidth="2.1"
      strokeLinecap="round"
      strokeLinejoin="round"
    />

    {/* Garfo Dianteiro */}
    <path
      d="M22.3 13.5L24.5 22"
      stroke={primaryColor}
      strokeWidth="2.1"
      strokeLinecap="round"
    />

    {/* Assento Ergonômico e Tanque */}
    <path
      d="M11 15.8C11 14.8 12.2 14.5 14.8 14.8C16.2 15 17 15.2 18.2 13.8C19 13 20.8 13.2 21.5 14.2L19.5 16.8H11.5L11 15.8Z"
      fill={primaryColor}
    />

    {/* Detalhe Carenagem Terracota */}
    <path
      d="M17.5 14.2L22.2 12.8L21 17.2L17.5 16V14.2Z"
      fill={accentColor}
    />

    {/* Farol LED Dianteiro */}
    <path
      d="M23.2 11.5H25.2C25.8 11.5 26.2 12 26.2 12.5C26.2 13 25.8 13.5 25.2 13.5H23.2V11.5Z"
      fill="#FBBF24"
    />

    {/* Baú Express EntregaCondo com cantos arredondados */}
    <rect
      x="3.5"
      y="7.5"
      width="9.5"
      height="8"
      rx="2"
      fill={accentColor}
      stroke={primaryColor}
      strokeWidth="1.6"
    />
    {/* Tampa superior do baú */}
    <path
      d="M4.2 10.2H12.3"
      stroke="#FFFFFF"
      strokeOpacity="0.45"
      strokeWidth="1.2"
      strokeLinecap="round"
    />
    {/* Faixa refletiva central no baú */}
    <rect x="5.2" y="11.8" width="6" height="1.8" rx="0.9" fill="#FFFFFF" fillOpacity="0.92" />
  </svg>
);

/**
 * Ícone SVG de Furgão / Fiorino / Utilitário Leve (Design System EntregaCondo)
 * Visual moderno com compartimento de carga aerodinâmico em terracota,
 * cabine integrada e vidro chanfrado.
 */
export const IconeCarro: React.FC<VehicleIconProps> = ({
  size = 28,
  className = '',
  primaryColor = '#0F1B2D',
  accentColor = '#EA580C',
  ...props
}) => (
  <svg
    width={size}
    height={size}
    viewBox="0 0 32 32"
    fill="none"
    xmlns="http://www.w3.org/2000/svg"
    className={className}
    {...props}
  >
    {/* Sombra de base */}
    <ellipse cx="16" cy="26.5" rx="13" ry="1.5" fill={primaryColor} fillOpacity="0.18" />

    {/* Compartimento de Carga (Furgão Terracota) */}
    <path
      d="M3.5 11.5C3.5 9.84315 4.84315 8.5 6.5 8.5H17.5V21H3.5V11.5Z"
      fill={accentColor}
      stroke={primaryColor}
      strokeWidth="1.7"
      strokeLinejoin="round"
    />

    {/* Detalhe de Fita / Pacote EntregaCondo no Baú */}
    <rect x="6" y="12" width="8.5" height="2" rx="1" fill="#FFFFFF" fillOpacity="0.92" />
    <rect x="6" y="15.2" width="5" height="1.3" rx="0.65" fill="#FFFFFF" fillOpacity="0.45" />

    {/* Cabine Dianteira Integrada */}
    <path
      d="M17.5 10H21.8C23.1 10 24.2 10.7 24.8 11.9L27.2 16.2C27.9 16.6 28.5 17.4 28.5 18.4V20C28.5 20.6 28 21 27.4 21H17.5V10Z"
      fill="#F8FAFC"
      stroke={primaryColor}
      strokeWidth="1.7"
      strokeLinejoin="round"
    />

    {/* Para-brisa e Janela Lateral */}
    <path
      d="M19.2 11.8H21.8C22.4 11.8 23 12.1 23.3 12.7L25 15.8H19.2V11.8Z"
      fill="#0EA5E9"
      fillOpacity="0.85"
      stroke="#0F1B2D"
      strokeWidth="1.2"
      strokeLinejoin="round"
    />

    {/* Farol LED Dianteiro */}
    <rect x="26.5" y="17.2" width="2" height="2.2" rx="0.8" fill="#FBBF24" />

    {/* Roda Traseira */}
    <circle cx="8.8" cy="22" r="3.8" fill="#1E293B" stroke={primaryColor} strokeWidth="2" />
    <circle cx="8.8" cy="22" r="1.6" fill="#F8FAFC" />

    {/* Roda Dianteira */}
    <circle cx="22.8" cy="22" r="3.8" fill="#1E293B" stroke={primaryColor} strokeWidth="2" />
    <circle cx="22.8" cy="22" r="1.6" fill="#F8FAFC" />
  </svg>
);

/**
 * Ícone SVG de Caminhão VUC / Baú Urbano (Design System EntregaCondo)
 * Baú estruturado em terracota com frisos, cabine elevada e eixo duplo.
 */
export const IconeCaminhao: React.FC<VehicleIconProps> = ({
  size = 28,
  className = '',
  primaryColor = '#0F1B2D',
  accentColor = '#EA580C',
  ...props
}) => (
  <svg
    width={size}
    height={size}
    viewBox="0 0 32 32"
    fill="none"
    xmlns="http://www.w3.org/2000/svg"
    className={className}
    {...props}
  >
    {/* Sombra de base */}
    <ellipse cx="16" cy="26.8" rx="13.5" ry="1.5" fill={primaryColor} fillOpacity="0.18" />

    {/* Baú de Carga Principal VUC */}
    <rect
      x="2.5"
      y="6.5"
      width="16"
      height="14.5"
      rx="2.2"
      fill={accentColor}
      stroke={primaryColor}
      strokeWidth="1.7"
    />

    {/* Frisos Verticais Estruturais do Baú */}
    <line x1="7.5" y1="7.5" x2="7.5" y2="20" stroke="#FFFFFF" strokeOpacity="0.25" strokeWidth="1.2" />
    <line x1="13" y1="7.5" x2="13" y2="20" stroke="#FFFFFF" strokeOpacity="0.25" strokeWidth="1.2" />

    {/* Faixa Identidade EntregaCondo no Baú */}
    <rect x="4.8" y="11.5" width="11.4" height="2.2" rx="1.1" fill="#FFFFFF" fillOpacity="0.92" />
    <rect x="4.8" y="15" width="6.5" height="1.3" rx="0.65" fill="#FFFFFF" fillOpacity="0.5" />

    {/* Cabine Avançada do VUC */}
    <path
      d="M18.5 9.5H23.8C24.9 9.5 25.8 10.2 26.2 11.2L28.2 16V20.2C28.2 20.9 27.6 21.5 26.9 21.5H18.5V9.5Z"
      fill="#F8FAFC"
      stroke={primaryColor}
      strokeWidth="1.7"
      strokeLinejoin="round"
    />

    {/* Defletor Aerodinâmico no Topo da Cabine */}
    <path
      d="M18.5 7.2C20.2 7.2 21.8 8 22.5 9.5H18.5V7.2Z"
      fill={accentColor}
      stroke={primaryColor}
      strokeWidth="1.3"
      strokeLinejoin="round"
    />

    {/* Janela Panorâmica da Cabine */}
    <path
      d="M20.2 11.2H23.6C24.1 11.2 24.6 11.5 24.8 12L26.2 15.4H20.2V11.2Z"
      fill="#0EA5E9"
      fillOpacity="0.85"
      stroke="#0F1B2D"
      strokeWidth="1.2"
      strokeLinejoin="round"
    />

    {/* Farol Dianteiro */}
    <rect x="26.6" y="17.2" width="1.9" height="2.4" rx="0.7" fill="#FBBF24" />

    {/* Rodas Traseiras e Dianteira */}
    <circle cx="7.2" cy="22.5" r="3.4" fill="#1E293B" stroke={primaryColor} strokeWidth="1.9" />
    <circle cx="7.2" cy="22.5" r="1.4" fill="#F8FAFC" />

    <circle cx="13.8" cy="22.5" r="3.4" fill="#1E293B" stroke={primaryColor} strokeWidth="1.9" />
    <circle cx="13.8" cy="22.5" r="1.4" fill="#F8FAFC" />

    <circle cx="24" cy="22.5" r="3.4" fill="#1E293B" stroke={primaryColor} strokeWidth="1.9" />
    <circle cx="24" cy="22.5" r="1.4" fill="#F8FAFC" />
  </svg>
);

/**
 * Ícone SVG de Sede / Ponto de Partida (Cubo Isométrico EntregaCondo)
 */
export const IconeSedePartida: React.FC<{ size?: number; className?: string }> = ({
  size = 16,
  className = '',
}) => (
  <svg
    width={size}
    height={size}
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth="2.2"
    strokeLinecap="round"
    strokeLinejoin="round"
    className={className}
  >
    <path d="M12 2L21 7L12 12L3 7L12 2Z" fill="currentColor" fillOpacity="0.25" />
    <path d="M3 7V17L12 22V12L3 7Z" fill="currentColor" fillOpacity="0.15" />
    <path d="M21 7V17L12 22V12L21 7Z" fill="currentColor" fillOpacity="0.35" />
    <line x1="7.5" y1="4.5" x2="16.5" y2="9.5" />
    <line x1="12" y1="12" x2="12" y2="22" />
  </svg>
);

/**
 * Retorna o ícone SVG apropriado conforme o tipo de veículo do motorista
 */
export const ObterIconeVeiculo: React.FC<{
  tipo: TipoVeiculoIcone | string;
  size?: number;
  className?: string;
  primaryColor?: string;
  accentColor?: string;
}> = ({ tipo, size = 24, className, primaryColor, accentColor }) => {
  const norm = String(tipo || 'moto').toLowerCase();

  if (norm.includes('caminh') || norm.includes('truck') || norm.includes('pesado') || norm.includes('vuc')) {
    return (
      <IconeCaminhao
        size={size}
        className={className}
        primaryColor={primaryColor}
        accentColor={accentColor}
      />
    );
  }
  if (
    norm.includes('carro') ||
    norm.includes('fiorino') ||
    norm.includes('van') ||
    norm.includes('strada') ||
    norm.includes('auto') ||
    norm.includes('utilit')
  ) {
    return (
      <IconeCarro
        size={size}
        className={className}
        primaryColor={primaryColor}
        accentColor={accentColor}
      />
    );
  }
  return (
    <IconeMoto
      size={size}
      className={className}
      primaryColor={primaryColor}
      accentColor={accentColor}
    />
  );
};
