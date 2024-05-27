'use client';

import { useState } from "react";
import { useMutation } from "@tanstack/react-query";
import { Flip, ToastContainer, toast } from 'react-toastify';
import 'react-toastify/dist/ReactToastify.css';

interface PromptProps {
  sendToQ: (img: string, count: number) => Promise<void>;
}
export const Prompt: React.FC<PromptProps> = ({ sendToQ }) => {

  const [prompt, setPrompt] = useState('')
  const [count, setCount] = useState(1)
  const mutation = useMutation<any, any, [string, number]>({
    mutationFn: ([img, count]: [string, number]) => {
      return sendToQ(img, count);
    },
  });
  const generateOnClick = () => {
    if (prompt) {
      toast.success("Task has been added to job queue 🤖");
      mutation.mutate([prompt, count]);
      setPrompt('');
      setCount(1);
    }
  }

  return (
    <div className="flex flex-col gap-5">
      <div className="flex items-left">
        <div className="pt-5 mr-2">Prompt:</div>
        <input className="backdrop-blur-2xl dark:from-inherit static w-auto rounded-xl border bg-gray-100 p-4 dark:bg-zinc-800/30 prompt"
            name="prompt" placeholder='Yellow submarine' value={prompt} onChange={e => setPrompt(e.target.value)}>
        </input>
        <button className="ml-5 bg-transparent border border-slate-200 rounded-xl dark:border-slate-700 dark:text-slate-100 p-4 generate" onClick={generateOnClick}>Generate</button>
        <ToastContainer 
          position="top-right"
          autoClose={7000}
          hideProgressBar={false}
          newestOnTop={false}
          closeOnClick
          rtl={false}
          pauseOnFocusLoss
          draggable
          pauseOnHover
          theme="dark"
          transition={Flip}
        />
      </div>
      Number of images: {count} <input type="range" max="4" min="1" value={count} onChange={e => setCount(+e.target.value)} className="text-slate-100"/>
    </div>
  )
}
