'use client';

import { useState } from "react";
import { useMutation } from "@tanstack/react-query";

interface PromptProps {
  sendToQ: (img: string) => Promise<void>;
}
export const Prompt: React.FC<PromptProps> = ({ sendToQ }) => {

  const [prompt, setPrompt] = useState('')
  const mutation = useMutation({
    mutationFn: (img: string) => {
      return sendToQ(img);
    },
  });

  return (
    <div className="flex items-left">
      <div className="pb-6 pt-8 mr-2">Prompt:</div>
      <input className="backdrop-blur-2xl dark:border-neutral-800  dark:from-inherit lg:static lg:w-auto  lg:rounded-xl lg:border lg:bg-gray-100 lg:p-4 lg:dark:bg-zinc-800/30"
          name="prompt" placeholder='Yellow submarine' value={prompt} onChange={e => setPrompt(e.target.value)}>
      </input>
      <button className="ml-5 bg-transparent border border-slate-200 hover:bg-slate-800 dark:border-slate-700 dark:text-slate-100 p-5" onClick={()=>{mutation.mutate(prompt); setPrompt('');}}>Generate</button>
    </div>
  )
}
