import React from 'react';

interface KPICardProps {
  label: string;
  value: string | number;
  subtext: string;
  subtextColor?: string;
  progressPercent?: number;
  progressBarColor?: string;
  valueColor?: string;
}

export const KPICard: React.FC<KPICardProps> = ({
  label,
  value,
  subtext,
  subtextColor = 'text-[#516074]',
  progressPercent,
  progressBarColor = 'bg-[#15803D]',
  valueColor = 'text-[#0F1B2D]',
}) => {
  return (
    <div className="bg-white border border-gray-300 rounded-[14px] p-[18px] flex flex-col gap-1.5 shadow-card transition-all hover:border-slate-400">
      <div className="text-[13px] font-semibold text-[#516074]">
        {label}
      </div>
      
      <div className={`text-[30px] font-extrabold leading-[1.1] ${valueColor}`}>
        {value}
      </div>

      {typeof progressPercent === 'number' && (
        <div className="h-1.5 rounded-[3px] bg-[#E4E9F0] overflow-hidden mt-0.5">
          <div
            style={{ width: `${progressPercent}%` }}
            className={`h-full ${progressBarColor} rounded-[3px] transition-all duration-500`}
          />
        </div>
      )}

      <div className={`text-xs ${subtextColor}`}>
        {subtext}
      </div>
    </div>
  );
};
