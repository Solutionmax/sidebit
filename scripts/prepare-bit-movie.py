#!/usr/bin/env python3
"""Key, frame and optionally soften the loop boundary of a generated character movie.
Requires FFmpeg >=7 (older ProRes alpha streams are rejected by Apple's decoder)
and Pillow only for reading bounding boxes. No provider calls or credentials.
"""
import argparse,json,math,os,subprocess
from pathlib import Path
from PIL import Image
p=argparse.ArgumentParser();p.add_argument('input',type=Path);p.add_argument('output',type=Path);p.add_argument('--loop',action='store_true');p.add_argument('--key-color',choices=['green','blue'],default='green');p.add_argument('--ffmpeg',default=os.environ.get('SNIPKIN_FFMPEG','ffmpeg'));args=p.parse_args()
args.output.mkdir(parents=True,exist_ok=True)
ff=args.ffmpeg
info=json.loads(subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0','-show_entries','stream=width,height','-of','json',str(args.input)]))['streams'][0]
w=768;h=2*round(info['height']/info['width']*w/2)
keyhex='0x00FF00' if args.key_color=='green' else '0x0000FF'
spill='green=-1:blue=0' if args.key_color=='green' else 'green=0:blue=-1'
key=f'format=rgba,colorkey={keyhex}:0.18:0.10,despill=type={args.key_color}:mix=0.5:{spill}'
proc=subprocess.Popen([ff,'-hide_banner','-loglevel','error','-i',str(args.input),'-vf',f'scale={w}:{h},{key},alphaextract','-f','rawvideo','-pix_fmt','gray','-'],stdout=subprocess.PIPE)
bounds=None;frames=0
while True:
 data=proc.stdout.read(w*h)
 if not data:break
 if len(data)!=w*h:raise RuntimeError('Incomplete alpha frame')
 box=Image.frombytes('L',(w,h),data).point(lambda v:255 if v>=128 else 0).getbbox()
 if box:bounds=box if bounds is None else (min(bounds[0],box[0]),min(bounds[1],box[1]),max(bounds[2],box[2]),max(bounds[3],box[3]))
 frames+=1
if proc.wait()!=0 or bounds is None:raise RuntimeError('Alpha analysis failed')
x=max(0,bounds[0]-10)//2*2;y=max(0,bounds[1]-10)//2*2
cw=min(w-x,math.ceil((bounds[2]-x+10)/2)*2);ch=min(h-y,math.ceil((bounds[3]-y+10)/2)*2)
size=min(440/cw,440/ch);ow=max(2,round(cw*size/2)*2);oh=max(2,round(ch*size/2)*2)
filter=f'scale={w}:{h},{key},crop={cw}:{ch}:{x}:{y},scale={ow}:{oh},pad=512:512:(ow-iw)/2:480-ih:color=black@0,setsar=1'
if args.loop:
 # Tail blends into the head; the resulting 9.5s clip begins at original t=.5.
 # Both blend sides keep identical matte/framing and the source is never overwritten.
 graph=f'[0:v]fps=24,trim=duration=10,setpts=PTS-STARTPTS,{filter},split=3[body][tail][head];[body]trim=start=0.5:end=9.5,setpts=PTS-STARTPTS[b];[tail]trim=start=9.5:end=10,setpts=PTS-STARTPTS[t];[head]trim=start=0:end=0.5,setpts=PTS-STARTPTS[h];[t][h]blend=all_expr=\'A*(1-min(T/0.458333333,1))+B*min(T/0.458333333,1)\'[join];[b][join]concat=n=2:v=1:a=0[out]'
else:graph=f'[0:v]fps=24,trim=duration=10,setpts=PTS-STARTPTS,{filter}[out]'
subprocess.run([ff,'-hide_banner','-loglevel','error','-y','-i',str(args.input),'-filter_complex',graph,'-map','[out]','-an','-r','24','-fps_mode','cfr','-c:v','prores_ks','-profile:v','4','-pix_fmt','yuva444p10le','-threads','4',str(args.output/'prores.mov')],check=True)
subprocess.run([ff,'-hide_banner','-loglevel','error','-y','-i',str(args.output/'prores.mov'),'-frames:v','1',str(args.output/'poster.png')],check=True)
subprocess.run([ff,'-hide_banner','-loglevel','error','-y','-f','lavfi','-i','color=c=0xf7f1e8:s=512x512:r=24','-i',str(args.output/'prores.mov'),'-filter_complex','[0:v][1:v]overlay=shortest=1:format=auto,format=yuv420p[out]','-map','[out]','-an','-c:v','libx264','-preset','fast','-crf','19','-movflags','+faststart','-threads','4',str(args.output/'preview.mp4')],check=True)
subprocess.run([ff,'-hide_banner','-loglevel','error','-y','-i',str(args.output/'preview.mp4'),'-vf','fps=1,scale=180:180,tile=5x2','-frames:v','1',str(args.output/'contact.png')],check=True)
report={'keyColor':args.key_color,'framesAnalyzed':frames,'sourceSize':[info['width'],info['height']],'scaledCrop':[x,y,cw,ch],'contentSize':[ow,oh],'canvasSize':[512,512],'loopBlendSeconds':0.5 if args.loop else 0,'ffmpegVersion':subprocess.check_output([ff,'-version'],text=True).splitlines()[0]}
(args.output/'processing.json').write_text(json.dumps(report,indent=2));print(json.dumps(report))
