'use server';


import Image from "next/image";
import { sendToQueue } from "./services/images";
import { Prompt } from "./prompt";
import { GeneratedImages } from "./generatedImages";

const Home = async () => {  
  return (
    <>
    <nav
      className="relative flex w-full flex-wrap items-center justify-between bg-zinc-50 py-2 shadow-dark-mild dark:bg-neutral-800 lg:py-2">
      <div className="flex w-full flex-wrap items-center justify-between px-3">
        <div className="ms-2">
          <a className="text-xl text-sky-400 " href="https://github.com/kedify/examples/tree/main/samples/stable-diffusion" target="_blank">Autoscaled Stable Diffusion</a> <span className="sm:text-sky-200 hidden sm:inline-block">(application deployed in Kubenetes utilizing KEDA for autoscaling the load)</span>
        </div>
          <a
            href="https://github.com/kedify/examples/tree/main/samples/stable-diffusion"
            target="_blank"
          >
          <Image
            className="ml-auto invert"
            src="/github-mark.svg"
            alt="GH repo"
            width={30}
            height={30}
            priority
          />
        </a>
      </div>
    </nav>

    <main className="flex min-h-screen flex-col items-center justify-between p-5">
      <div className="z-10 w-full max-w-5xl items-center justify-between font-mono text-sm lg:flex pt-24 pl-6">
        <Prompt sendToQ={sendToQueue} />
        <div>
          <a
            className="pointer-events-none flex place-items-center gap-2 p-8 lg:pointer-events-auto lg:p-0"
            href="https://kedify.io"
            target="_blank"
          >
            <div className="flex flex-wrap gap-2">
              By{" "}
              <Image
                src="/logo-kedify.svg"
                alt="Kedify Logo"
                width={100}
                height={24}
                priority
              />
            </div>
          </a>
          <div className="mt-1">
            {/* todo replace w/ correct url once the pr gets merged */}
            <a className="hover:text-sky-400 hover:underline underline-offset-8" href="https://dashboard.kedify.io/clusters/7341d179-1efd-4c15-8201-0a18a15f959c/scaledobjects/stable-diff/stable-diff-app" target="_blank">check the dashboard</a>
          </div>
        </div>
      </div>
      <GeneratedImages />

      <div className="relative z-[-1] flex place-items-center before:absolute before:h-[300px] before:w-full before:-translate-x-1/2 before:rounded-full before:bg-gradient-radial before:from-white before:to-transparent before:blur-2xl
                      before:content-[''] after:absolute after:-z-20 after:h-[180px] after:w-full after:translate-x-1/3 after:bg-gradient-conic after:from-sky-200 after:via-blue-200 after:blur-2xl after:content-[''] before:bg-gradient-to-br
                      before:from-transparent before:to-blue-700 before:opacity-10 after:from-sky-900 after:via-[#0141ff] after:opacity-40 sm:before:w-[480px] sm:after:w-[240px] before:lg:h-[360px]">
        <Image
          className="relative drop-shadow-[0_0_0.3rem_#ffffff70]"
          src="/logo-kedify-mobile.svg"
          alt="Kedify Logo small"
          width={80}
          height={20}
          priority
        />
      </div>
      <div className="fixed bottom-0 left-0 flex h-48 w-full items-end justify-center bg-gradient-to-t from-black via-black from-black via-black lg:static lg:size-auto lg:bg-none"></div>
    </main>
    </>
  );
}

export default Home;
