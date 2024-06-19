'use client';

import { useRef, useState } from "react";
import { useMutation } from "@tanstack/react-query";
import { Flip, ToastContainer, toast } from 'react-toastify';
import 'react-toastify/dist/ReactToastify.css';
import { Checkbox } from "@nextui-org/checkbox";
import { Tooltip } from "@nextui-org/react";

interface PromptProps {
  sendToQ: (img: string, inParallel: boolean, count: number) => Promise<void>;
}
export const Prompt: React.FC<PromptProps> = ({ sendToQ }) => {

  const [prompt, setPrompt] = useState('')
  const [count, setCount] = useState(1)
  const [inParallel, setInParallel] = useState(true)
  const promptRef = useRef(null);
  const focusPrompt = () => {
    setTimeout(() => {
      if (promptRef && promptRef.current) {
        const promptField: any = promptRef;
        promptField.current.focus();
      }
    }, 200)
  }
  const mutation = useMutation<any, any, [string, boolean, number]>({
    mutationFn: ([img, inParallel, count]: [string, boolean, number]) => {
      console.log(inParallel)
      return sendToQ(img, inParallel, count);
    },
  });
  const safetyCheck = (prompt: string) => {
    const stopList = ["boob", "tits", "vagina", "penis", "dick", "naked", "nude", "fuck", "coitus", "sex", "shit", "blood", "murder", "dead"];
    return stopList.some(w => prompt.toLowerCase().includes(w));
  }

  const generateOnClick = () => {
    if (prompt) {
      if (safetyCheck(prompt)) {
        toast.warning("Please don't use this tool for creating NSFW content.");
        focusPrompt();
        return
      }
      toast.success("Task has been added to job queue 🤖");
      mutation.mutate([prompt, inParallel, count]);
      setPrompt('');
      setCount(1);
      focusPrompt();
    }
  }
  focusPrompt();
  
  return (
    <div className="flex flex-col gap-5">
      <div className="flex items-left">
        <div className="pt-5 mr-2">Prompt:</div>
        <input className="backdrop-blur-2xl from-inherit static max-w-36 sm:w-auto sm:max-w-none rounded-xl border bg-gray-100 sm:pr-4 sm:pl-4 p-2 py-4 bg-zinc-800/30 prompt"
            name="prompt" ref={promptRef} placeholder='Yellow submarine' value={prompt} onChange={e => setPrompt(e.target.value)}>
        </input>
        <button className="sm:ml-5 ml-2 bg-transparent border border-slate-200 rounded-xl border-slate-700 text-slate-100 sm:pr-4 sm:pl-4 p-2 py-4 generate" onClick={generateOnClick}>Generate</button>
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
      <div className="flex gap-4">
        Number of images: {count}
        <Tooltip color="primary" content={
          <div className="bg-slate-900 p-4 rounded-md">
            <div className="text-small  mb-3">When selected {count > 1 ? count : ''} requests will be sent to the message queue.<br /> Each can be processed by a different pod.<br />
              Otherwise, one task {count > 1 ? `for ${count} images` : ''} will be created on a single pod.
            </div>
          </div>
          } delay={500}>
          <span className="ml-16">in parallel</span>
        </Tooltip>
        <Checkbox defaultSelected={inParallel} onChange={e => setInParallel(e.target.checked)} className="text-[#34ace3]" size="lg" />
      </div>
      <input type="range" max="4" min="1" value={count} onChange={e => setCount(+e.target.value)} className="text-slate-100 max-w-80 sm:w-auto sm:max-w-none"/>
    </div>
  )
}
