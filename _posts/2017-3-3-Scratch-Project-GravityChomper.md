---
title: Scratch Project - Gravity Chomper
layout: post
comments: True
category: Scratch
tags:
 - Sprite Cloning
 - Gravity
 
---

Project Walk-through for the [Scratch](http//scratch.mit.edu) Class Taught at [The Made](https//themade.org/scratch). A simple character
moves around eating floating objects. Gravity can be controlled to either draw or repel nearby
objects.

---

# Gravity Chomper!

Gravity Chomper is a game where you play as a small gravity beast. As it spins happily through a 
cloud of foods help it eat its favorites (apples, basketballs) while avoiding the foods it hates 
(bananas). 

* 60 Second Time Limit
* Pressing **A** increases its gravity and **D** causes it to repel!
* Use the arrow keys to navigate

![Final Project](/images/gravitychomper/gc_fullgame.gif)

* [Step 0 Setup](#step-0-remove-the-cat)
* [Step 1 Create a Gravity Beast](#step-1-creating-a-gravity-beast)
* [Step 2 Player Controls](#step-2-player-controls-for-gravitica)
* [Step 3 Apple Swarm](#step-3-apple-swarm)
* [Step 4 Gravity](#step-4-gravity)
* [Step 5 Points](#step-5-points)

---

## Step 0 Remove the Cat

We won't be using the cat in this project so the first thing to do is to delete him. **Right Click** 
on the Scratch Cat and select **Delete** from the drop-down menu.

---

![Delete the Cat](/images/gravitychomper/gc_deletecat.gif)

## Step 1 Creating a Gravity Beast

### Step 1.1 Choose Draw a new Sprite

In the **Sprites Panel** click on the icon that looks like a paintbrush next to the words 
"New Sprite". This Creates a  new **Sprite** which you will be able to paint.

![Create New Sprite](/images/gravitychomper/gc_paintnewsprite.gif)

---

### Step 1.2 Draw your Gravity Beast!

You are free to draw your beast however you like but it helps to have a small and circular 
shaped creature so it will be easy to control while it spins.

---

### Step 1.3 Rename the Sprite

In the **Sprite Panel** you now have **Sprite1**. This is not a very descriptive
name so lets rename it. Click on the **Blue I** in the upper left portion of your
Sprite's picture. Then type in a new name like "Gravitica"

![Rename the Sprite](/images/gravitychomper/gc_rename.gif)

---

## Step 2 Player Controls for Gravitica

Click on Gravitica and then on the **Scripts** on the top of the middle of
the screen. 

![To Scripts Tab](/images/gravitychomper/gc_toscripttab.gif)

---

### Step 2.1 When Green Flag Clicked

The player is allowed to control Gravitica for 60 seconds until the game is
over. This means we need to have a loop checking for the player's button 
presses for 60 Seconds.

Grab a ![When Green Flag CLicked]({{ site.scratch }}when_green_flag_clicked.png) block from the **Events** Category. This
block is the start of your application. Everytime you click on the **Green Flag** this triggers 
the start of the game and all the blocks under the ![When Green Flag CLicked]({{ site.scratch }}when_green_flag_clicked.png)
block will go into action.

---

### Step 2.2 Event Loop

Underneath the ![When Green Flag CLicked]({{ site.scratch }}when_green_flag_clicked.png) block place a 
![Repeat Until]({{ site.scratch }}repeat_until_().png) block from the **Events** category. 
All of the blocks we place within this C shaped block will be executed
until the block we place in the **<>** is true. 

![Event Loop](/images/gravitychomper/gc_eventloop.gif)

---

### Step 2.3 Event Loop Condition (60 Seconds)
Since the **<>** is a hexgon we need a hexagon block to fit inside it. We can find 
hexagon blocks in the **Operators** category. Choose operators and grab a
 ![() < ()]({{ site.scratch }}()_is_Less_Than_().png) block. The **[]** is a place where we can either type in our own
 number or place a block. We want the condition to be false until the
 ![timer]({{ site.scratch}}timer.png) block from **Sensing** is greater than **60**
 
![condition](/images/gravitychomper/gc_econd.png)

---

### Step 2.4 Controls

Each of our player controls will be an ![if]({{ site.scratch}}if_().png) block 
from the **Control** category checking whether a key has been pressed using the 
 ![key pressed]({{ site.scratch}}key_()_pressed.png) block from the **Sensing** Category.
 
 Create an **if** block and place the ![key pressed]({{ site.scratch}}key_()_pressed.png) 
 block inside it. Then 
 **Right Click** on the **if** Block and duplicate it 4 times.
 
![controls](/images/gravitychomper/gc_controlif.gif)
 
#### Up

Scratch uses the same coordinate system that you are probably used to
from school. In this systems the vertical (down-up) position of an object 
is determined by ![y]({{site.scratch}}y_position.png) and the horizontal 
(left-right) is controlled by ![x]({{site.scratch}}x_position.png).

For upwards movement we need to increase **y**. Change the 
![key pressed]({{ site.scratch}}key_()_pressed.png) of the **first if** statement 
into sensing the **up arrow** by clicking on the **small black triangle** next to 
the word **space**. Add a ![change y by]({{ site.scratch}}change_y_by_().png) 
block from the motion category to the if statement. Set the value inside to **5**.

#### Down

For downwards movement we need to decrease **y**. Change the **second if**
statement to the **down arrow** and add a ![change y by]({{ site.scratch}}change_y_by_().png) 
 block from the **Motion** category. Set the value to **-5**

#### Left

For leftwards movement we need to decrease **x**. Change the **third if**
statement to the **down arrow** and add a  ![change x by]({{ site.scratch}}change_x_by_().png)  
 block from the **Motion** category. Set the value to **-5**

#### Right

For rightwards movement we need to decrease **x**. Change the **fourth if**
statement to the **down arrow** and add a  ![change x by]({{ site.scratch}}change_x_by_().png)  
 block from the **Motion** category. Set the value to **5**

---

### Step 2 End Move the if blocks into the Event Loop and Test it out

The code should now look like this
![step2end](/images/gravitychomper/gc_step2end.png)

Press the green flag and make sure you can move
your character with the arrow buttons on the keyboard. After
60 seconds the character should stop moving.

Challanges
 * Can you change the player speed?
 * Can you change the time limit?
 * Can you make the player say the time left?
 
---

## Step 3 Apple Swarm

### Step 3.1 Grab the apple sprite from the Sprite Library

Click on the little alien next to **New sprite** and select
the apple from the library. Click on the **Apple** picture in the
**Sprites** Panel and start adding scripts to the **APPLE**

---

### Step 3.2 Make the apple a good size

![apple size](/images/gravitychomper/gc_31.png) 

---

### Step 3.3 Create lots of apple clones

![apple clones](/images/gravitychomper/gc_32.png)

---

### Step 3.4 Create direction for **this sprite only**

![direction creation](/images/gravitychomper/gc_33.png)

---

### Step 3.5 Create our clone movement instructions

![movement](/images/gravitychomper/gc_34.png)

---

### Step 3.6 Hide the apple

![movement](/images/gravitychomper/gc_35.png)

---

### Step 3.6 Test it out

At this point when you press the green flag there should be a swarm of apples
going across the screen.

Challenges
* Can you make the swarm move faster and slower?
* Can you give each apple a different speed?
* Can you make apples come from both sides of the screen?

---

## Step 4 Gravity

** Click on the Stage To the Left of the Sprites Panel and above "New Backdrop" **

---

### Step 4.1 Create Gravity variable for Everyone

![make gravity](/images/gravitychomper/gc_41.png) 

---

### Step 4.2 Create Gravity controls and bounds

![gravity controls](/images/gravitychomper/gc_42.png) 

---

** Click on the Apple Sprite in the Sprite Panel **

### Step 4.4 Have Apples effected by gravity

![apple gravity](/images/gravitychomper/gc_43.png) 

---

### Step 4.5 Test it out

At this point the apples should go towards the player when you press A and aways when
you press S. 

Challenges
* Can you put a max limit on gravity strength?
* Can you make it so that objects that are very far away are not effected by gravity as much?
* Can you make the strength of the gravity effect the movement speed of the player?

---

## Step 5 Points

### Step 5.0 Add variables for things being eaten

** Click on the Stage To the Left of the Sprites Panel and above "New Backdrop" **

![make count variables](/images/gravitychomper/gc_50.png) 

Reset them all to 0 on Green Flag Clicked

![init variables](/images/gravitychomper/gc_501.png) 

---

### Step 5.1 Make Apples disappear on being Eaten

![eat apples](/images/gravitychomper/gc_51.png) 

---

### Step 5.2 Add Bananas

Make a new sprite using the Banana from the sprite library. Copy all the code from the apple
by dragging it onto the picture of the Banana on the Sprite Pane. It will look like nothing 
happened until you click on the Banana and switch to it's scripts tab.

---

### Step 5.3 Modify Banana Code

![banana code](/images/gravitychomper/gc_53.png) 

---

### Step 5.4 Add Basketballs

Make a new sprite using the Basket Ball from the sprite library. Copy all the code from the apple
by dragging it onto the picture of the Banana on the Sprite Pane. It will look like nothing 
happened until you click on the Banana and switch to it's scripts tab.

---

### Step 5.5 Modify Basketball Code

![basket_ball](/images/gravitychomper/gc_55.png) 

---

### Step 5.6 Make Score for Everyone and Calculate Score

![score](/images/gravitychomper/gc_56.png) 

---

### Step 5.7 Test it out

### Final Challenges 

* Can you make the player freeze when they eat a bad item?
* Can you make the player get a speed bonus when they eat a good item?
* What other patterns can you make the fruits move in?
* Can you make the player spin based on when the gravity is on?
* Can you give the player bonus time if they eat a special item?
* Can you make the player say something if they get above a certain number of points?

