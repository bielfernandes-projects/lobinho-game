import Image from 'next/image'

export function PhoneFrame({ src, alt }: { src: string; alt: string }) {
  return (
    <div className="relative mx-auto w-48 aspect-[390/844] rounded-[2rem] border-4 border-neutral-800 bg-neutral-900 overflow-hidden shadow-lg shadow-red-900/20">
      <Image src={src} alt={alt} fill sizes="192px" className="object-cover" />
    </div>
  )
}
