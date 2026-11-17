"use dom"

import { type DOMProps } from "expo/dom"

import "@/global.css"

interface Props {
  footnote: string
  textColor?: string
  dom?: DOMProps
}

export default function Footnote({ footnote, textColor }: Props) {
  return (
    <>
      <style>{`
        * {
          color: ${textColor} !important;
        }
      `}</style>
      <div
        className="font-sans text-[15px] leading-relaxed"
        dangerouslySetInnerHTML={{ __html: footnote }}
      />
    </>
  )
}
