'use server';


import Image from "next/image";
import Link from "next/link";
import { useRouter } from "next/router";
import { getAvailableImages, sendToQueue } from "./services/images";
import { Prompt } from "./prompt";

const Home = async () => {
  const paths = getAvailableImages();
  console.log('prom');
  paths.then(p => {
    console.log(`image paths: ` + p)
  });

  // sendToQueue(new Date().toString());
  const images = (await paths).map((p, index) => {
    return {
      id: index,
      height: 512,
      width: 512,
      url: '/generated/' + p,
    }
  });

  return (
    <main className="flex min-h-screen flex-col items-center justify-between p-24">
      <div className="z-10 w-full max-w-5xl items-center justify-between font-mono text-sm lg:flex">
        <Prompt sendToQ={sendToQueue}></Prompt>
        <div className="fixed bottom-0 left-0 flex h-48 w-full items-end justify-center bg-gradient-to-t from-white via-white dark:from-black dark:via-black lg:static lg:size-auto lg:bg-none">
          <a
            className="pointer-events-none flex place-items-center gap-2 p-8 lg:pointer-events-auto lg:p-0"
            href="https://vercel.com?utm_source=create-next-app&utm_medium=appdir-template&utm_campaign=create-next-app"
            target="_blank"
            rel="noopener noreferrer"
          >
            By{" "}
            <Image
              src="/logo-kedify.svg"
              alt="Kedify Logo"
              width={100}
              height={24}
              priority
            />
          </a>
        </div>
      </div>

      {images.map(({ id, url, width, height }) => (
            <Link
              key={id}
              href={url}
              shallow
              className="after:content group relative mb-5 block w-full cursor-zoom-in after:pointer-events-none after:absolute after:inset-0 after:rounded-lg after:shadow-highlight"
            >
              <Image id={id.toString()}
                alt="Next.js Conf photo"
                className="transform rounded-lg brightness-90 transition will-change-auto group-hover:brightness-110"
                style={{ transform: "translate3d(0, 0, 0)" }}
                placeholder="blur"
                blurDataURL={url}
                src={url}
                width={width}
                height={height}
                sizes="(max-width: 640px) 100vw,
                  (max-width: 1280px) 50vw,
                  (max-width: 1536px) 33vw,
                  25vw"
              />
            </Link>
          ))}

      <div className="relative z-[-1] flex place-items-center before:absolute before:h-[300px] before:w-full before:-translate-x-1/2 before:rounded-full before:bg-gradient-radial before:from-white before:to-transparent before:blur-2xl before:content-[''] after:absolute after:-z-20 after:h-[180px] after:w-full after:translate-x-1/3 after:bg-gradient-conic after:from-sky-200 after:via-blue-200 after:blur-2xl after:content-[''] before:dark:bg-gradient-to-br before:dark:from-transparent before:dark:to-blue-700 before:dark:opacity-10 after:dark:from-sky-900 after:dark:via-[#0141ff] after:dark:opacity-40 sm:before:w-[480px] sm:after:w-[240px] before:lg:h-[360px]">
        <Image
          className="relative dark:drop-shadow-[0_0_0.3rem_#ffffff70]"
          src="/logo-kedify-mobile.svg"
          alt="Kedify Logo small"
          width={80}
          height={20}
          priority
        />
      </div>
    </main>
  );
}

export default Home;
