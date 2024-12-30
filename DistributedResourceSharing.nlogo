globals [
  tasks-completed             ;; total completed tasks
  deadlocks-detected          ;; counts deadlocks
  last-tasks-completed        ;; tasks completed from last check
  total-required-resources    ;; resources each task needs
  deadlock-check-interval     ;; how often we check for deadlocks
  max-wait-time               ;; max wait before retry
  backoff-range               ;; random wait time range for retry
  completion-rate             ;; shows the rate of tasks completed by "%"
]

breed [processes process]     ;; represents processes
breed [resources resource]    ;; represents resources needed by processes

processes-own [
  resources-held              ;; resources currently held
  task-completed?             ;; if task is finished
  waiting-time                ;; time waiting for resources
  task-start-time             ;; when task started
  task-duration               ;; time needed to finish
]

resources-own [
  held-by                     ;; which process holds the resource
  resource-id                 ;; ID for the resource
]

to setup
  clear-all
  print "Setting up resources and processes."

  ;; Initialize global settings
  set total-required-resources 2
  set deadlock-check-interval 50
  set max-wait-time 100
  set backoff-range 20
  set tasks-completed 0
  set deadlocks-detected 0
  set last-tasks-completed 0

  ;; Create resources
  create-resources num-resources [
    set shape "circle"
    set size 2
    set color yellow
    set held-by nobody
    set resource-id who
    setxy random-xcor random-ycor
    print (word "Resource " resource-id " created.")
  ]

  ;; Create processes
  create-processes num-processes [
    set shape "person"
    set size 2
    set color blue
    set task-completed? false
    set resources-held []
    set waiting-time 0
    set task-start-time 0
    set task-duration 0
    setxy random-xcor random-ycor
    print (word "Process " who " created.")
  ]

  ;; Ensure valid backoff range
  if backoff-range <= 0 [
    user-message "Backoff range must be positive!"
    stop
  ]

  reset-ticks
  print "Setup complete."
end

to go
  if ticks >= max-tick [ stop ]  ;; Stop when max ticks reached

  set completion-rate (tasks-completed / num-processes) * 100

  ;; Processes try to complete tasks
  ask processes [
    if not task-completed? [
      attempt-task
    ]
    set heading random 360
    forward 1
    set label (word "Held: " length resources-held " wait: " waiting-time)
  ]

  ;; Update resource labels
  ask resources [
    ifelse held-by = nobody [
      set label ""
    ] [
      set label word "Held by " [who] of held-by
    ]
  ]

  ;; Update plot
  set-current-plot "Tasks-Completed"
  set-current-plot-pen "Tasks-Completed-Pen"
  plot tasks-completed

  set-current-plot "Deadlocks-Detected"
  set-current-plot-pen "Deadlocks-Detected-Pen"
  plot deadlocks-detected

  if deadlock-detection [ detect-deadlocks ]

  tick
  wait 0.15
end

to attempt-task
  ;; Start tracking task if not started
  if task-start-time = 0 [
    set task-start-time ticks
  ]

  ;; If task duration is set, count down until done
  ifelse task-duration > 0 [
    set task-duration task-duration - 1
    if task-duration = 0 [
      perform-task
    ]
  ] [
    ;; Request resources if not holding enough
    request-all-resources

    ifelse length resources-held = total-required-resources [
      set task-duration 5
    ] [
      ;; Increment wait time if not enough resources
      set waiting-time waiting-time + 1
      if waiting-time > max-wait-time [
        print (word "Process " who " timed out, releasing resources.")
        release-resources
        set waiting-time 0
        set task-start-time 0
      ]
    ]
  ]
end

to request-all-resources
  ;; Check if enough resources are available
  if count resources < total-required-resources [
    user-message "Not enough resources available!"
    stop
  ]

  let available-resources resources with [held-by = nobody]

  if count available-resources < total-required-resources [
    stop
  ]

  ;; Get needed resources in order
  let sorted-available-resources sort available-resources
  let needed-resources sublist sorted-available-resources 0 total-required-resources

  ifelse two-phase-locking [
    ;; Lock all resources at once
    foreach needed-resources [
      res -> ask res [
        set held-by myself
        set color red
      ]
      set resources-held lput res resources-held
      print (word "Process " who " got resource " [resource-id] of res)
    ]
  ] [
    ;; Lock one resource at a time with wait
    foreach needed-resources [
      res -> ifelse [held-by] of res = nobody [
        ask res [
          set held-by myself
          set color red
        ]
        set resources-held lput res resources-held
        print (word "Process " who " got resource " [resource-id] of res)
      ] [
        set waiting-time waiting-time + random backoff-range
      ]
    ]
  ]
end

to perform-task
  set task-completed? true
  set tasks-completed tasks-completed + 1
  set color green
  print (word "Process " who " completed its task at tick " ticks)
  release-resources
  reset-task
end

to reset-task
  set task-completed? false
  set task-duration 0
  set waiting-time 0
  set resources-held []
  set task-start-time ticks
  set color blue
  print (word "Process " who " starting new task.")
end

to release-resources
  let released-ids []
  foreach resources-held [
    res -> ask res [
      set held-by nobody
      set color yellow
    ]
    set released-ids lput [resource-id] of res released-ids
  ]
  set resources-held []
  print (word "Process " who " released resources: " released-ids)
end

to detect-deadlocks
  if tasks-completed = last-tasks-completed [  ;; No progress is made
    let deadlock-occurred? false
    ask processes [
      if not task-completed? [
        ;; Check if all required resources are unavailable (held by others)
        let held-count count (resources with [held-by = myself])
        let needed-resources total-required-resources - held-count
        let available-resources count (resources with [held-by = nobody])
        if available-resources < needed-resources [
          set deadlock-occurred? true
        ]
      ]
    ]
    if deadlock-occurred? [
      print "Deadlock detected!"
      set deadlocks-detected deadlocks-detected + 1
      ;; Resolve deadlocks by releasing resources
      ask processes [
        if not task-completed? [
          release-resources
          print (word "Process " who " released resources to resolve deadlock.")
        ]
      ]
    ]
  ]
  ;; Update last-tasks-completed if progress is made
  if tasks-completed > last-tasks-completed [
    set last-tasks-completed tasks-completed
  ]
end

to-report all-tasks-completed?
  report all? processes [ task-completed? ]
end

to-report total-wait-time
  report sum [waiting-time] of processes
end

to-report average-wait-time
  let total-wait sum [waiting-time] of processes
  report total-wait / num-processes
end


to-report combined-metrics
  report (list tasks-completed deadlocks-detected average-wait-time)
end
@#$#@#$#@
GRAPHICS-WINDOW
724
29
1231
537
-1
-1
15.121212121212123
1
10
1
1
1
0
1
1
1
-16
16
-16
16
0
0
1
ticks
30.0

SLIDER
82
121
254
154
num-processes
num-processes
1
50
10.0
1
1
NIL
HORIZONTAL

SLIDER
82
166
255
199
num-resources
num-resources
1
50
10.0
1
1
NIL
HORIZONTAL

BUTTON
228
35
291
68
setup
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
335
33
398
66
Go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
310
135
422
180
Tasks Completed
tasks-completed
17
1
11

MONITOR
310
189
423
234
Deadlocks Detected 
deadlocks-detected
17
1
11

PLOT
79
357
367
539
Tasks-Completed
Time
Tasks Completed
0.0
50.0
0.0
50.0
true
false
"" ""
PENS
"Tasks-Completed-Pen" 1.0 0 -10899396 true "" "plot tasks-completed"

SWITCH
83
270
257
303
two-phase-locking
two-phase-locking
0
1
-1000

SLIDER
82
217
254
250
max-tick
max-tick
1
250
200.0
1
1
NIL
HORIZONTAL

PLOT
382
357
664
540
Deadlocks-Detected
time
Deadlocks Detected
0.0
50.0
0.0
50.0
true
false
"" ""
PENS
"Deadlocks-Detected-Pen" 1.0 0 -2674135 true "" "plot deadlocks-detected"

MONITOR
359
251
508
292
Task Completion Rate(%)
completion-rate
10
1
10

MONITOR
440
189
561
234
average-wait-time
average-wait-time
17
1
11

MONITOR
441
135
560
180
total-wait-time
total-wait-time
17
1
11

SWITCH
80
311
257
344
deadlock-detection
deadlock-detection
0
1
-1000

@#$#@#$#@
## WHAT IS IT?

This model is called Distributed Resource Sharing. It simulates a system of processes  that are attempting to complete tasks by acquiring 2 resources each process.

My simulation contains: 

	• 2PL (two-phase-locking), both shrinking and growing phase

	• Deadlock detection

	• Resource allocation

	• Resolution mechanism

	• Task management, in order to avoid deadlocks when the two-phase-locking    
          switch is off.

	• Backoff mechanism to retry resource acquisition after failure

## HOW IT WORKS

Setup:

   • A specified number of processes and resources are created.

   • Each process is initialized with variables like resource-held, task-completed?,        and waiting-time.


Go:

   • Once the Go button is pressed, each process tries to acquire the resources it          needs using the request-all-resources procedure.

   • If the process acquire 2 resources, it starts working on its task  
     (task-duration), and once it completes the task, it releases the resource and          starts a new task again.
   
   • If a process cannot acquire resources within a set max-wait-time, it releases its      the resources that holds and retries after a random backoff time.

   • If no progress is made when a process is trying to complete a task, the system         detects a deadlock (deadlock-detection). The deadlock is resolved by making            processes release the acquired resource.

Interface:

   As you can see, on the interface we have added Tasks Completed plot and Deadlocks 	   Detected plot that can track the process its made more visually. Five monitors are     added that tracks average-wait-time, tasks-completed, deadlocks-detected,     
   total-wait-time and Task Completion Rate. And also we have added three slider where
   you can edit how much processes you want (num-processes), how much resources you 
   want (num-resources) and max-tick. Last but not least, we have added a switch that
   disables two-phase-locking making the process acquire resources 1 by 1 avoiding        deadlocks, and a deadlock-detection switch that enables or disables deadlock
   detection.

## HOW TO USE IT

1) Adjust the sliders to the number of processes and resources you want.

2) Adjust switches, if you want to detect deadlocks or to use two-phase-locking and
   you can also set a max-tick number.

3) Click "setup" to initialize the simulation.

4) Click "go" to start the simulation.

5) Use the plots to monitor tasks completed and deadlocks detected.

6) I strongly suggest you to see the Command Center for more analytic information on
   how the simulation runs.

## THINGS TO NOTICE

In the simulation there are several things to notice.

  • Notice how some processes finish their task fast, while others are in a long wait.

  • You can also observe deadlocks, where processes get stuck because they all need  
    resources that are held by others.

  • For the deadlocks, you can also notice how the simulation resolves the deadlocks
    are made.

  • Plots are created to notice how many tasks are completed and how many deadlocks  
    often detected.

  • By changing the number of processes, resources and wait time each run, you can  
    notice how it affects the simulation on how smoothly everything runs.
.
  • Each process have labels, that show wait time and resource are currently holding.
.
  • You can also observe the colors are changing when the resources are free or held.

  • Lastly, you can observe the difference on how the system runs regarding to the
    two-phase-locking switch, if it is either enabled or disabled. 

## THINGS TO TRY

 • Adjust the number of processes and resources to see how it impacts task completion     and deadlocks.

 • Change the tick-time to observe how the simulation stops when they pass max-tick  
   number.

 • Put deadlock detection enabled or disabled and notice how the system behaves when      processes get stuck.
 
 • Watch specifically one process to understand why some finish tasks faster than   
   others.

 • Try "hard" setups, like very few resources or many processes, to test how the  
   system performs under pressure. 

 • Put two-phase-locking enabled or disabled to see how the simulation runs each time. 

## EXTENDING THE MODEL

    Some ways that you could extend the model are :

   • Make processes require different types or varying amounts of resources.

   • Add rules to prioritize some processes or resources.

   • Allow tasks to take different amounts of time or depend on other tasks finishing       first.

   • Improve deadlock handling with smarter resolution or prevent deadlocks with   
     resource ordering.

   • Make the simulation track new metrics, like average resource use or how long           processes wait.

   • Add more colors or labels to show if processes are waiting, working, or done.

   • Add a "manager" agent to help processes share resources better.

   • Try using the model for real-world problems, like traffic or managing computer   
     resources.

## CREDITS AND REFERENCE

This model was developed using NetLogo (Wilensky, 1999). For further details on the functionalities and usage of NetLogo, refer to the [NetLogo User Manual](https://ccl.northwestern.edu/netlogo/docs/).

## CITATION

Wilensky, U. (1999). NetLogo. Center for Connected Learning and Computer-Based Modeling, Northwestern University. Evanston, IL. [http://ccl.northwestern.edu/netlogo/](http://ccl.northwestern.edu/netlogo/)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="Distributed Resource Sharing" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <metric>tasks-completed</metric>
    <metric>deadlocks-detected</metric>
    <enumeratedValueSet variable="max-tick">
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-processes">
      <value value="5"/>
      <value value="10"/>
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="two-phase-locking">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="deadlock-detection">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-resources">
      <value value="5"/>
      <value value="10"/>
      <value value="20"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
