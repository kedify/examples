'use client';

import Link from "next/link";
import Image from "next/image";
import { useImagesQuery } from "./queries";
import {Tooltip} from "@nextui-org/react";
import moment from "moment";

interface GeneratedImagesProps {
}
export const GeneratedImages: React.FC<GeneratedImagesProps> = () => {
  const images = useImagesQuery()
  return (
    <div className="mt-20 flex flex-wrap">
      {images.data?.map(({ id, url, prompt, model, loraModel, generatedDate, width, height }) => (
        <Link
          key={id}
          href={url}
          shallow
          className="after:content group relative mb-5 block cursor-zoom-in after:pointer-events-none after:absolute after:inset-0 after:rounded-lg after:shadow-highlight"
        >
          <Tooltip color="primary" content={
            <div className="bg-slate-900 p-4 rounded-md">
              <div className="text-small font-bold mb-3">&quot;{prompt}&quot;</div>
              <div className="text-tiny">Generated: {moment(generatedDate).fromNow()}</div>
              <div className="text-tiny">Model: {model}</div>
              <div className="text-tiny">LoraModel: {loraModel}</div>
              <div className="text-tiny">Size: {width}x{height}px</div>
            </div>
          } delay={500}>
            <Image id={id.toString()}
              alt="Next.js Conf photo"
              className="ml-5 transform rounded-lg brightness-90 transition will-change-auto group-hover:brightness-110"
              style={{ transform: "translate3d(0, 0, 0)" }}
              placeholder="blur"
              blurDataURL={url}
              src={url}
              width={300}
              height={300}
              sizes="(max-width: 640px) 100vw,
                (max-width: 1280px) 50vw,
                (max-width: 1536px) 33vw,
                25vw"
            />
          </Tooltip>
        </Link>
      ))}
    </div>
  )
}
