# Youtube videos to guided recipe App

#### Name of the product: StoveChef

## Overview:

#### An app that takes a YouTube video link as input and converts it into a guided recipe that can be followed on a gas stove for cooking the exact recipe in the same manner.

## Product flow

#### Welcome Screen:

#### This screen will show the capabilities of the product. It will show an image which states what the product does and a CTA which is bottom-fixed, showing "Get Started"

#### Sign up or login

#### Users can login using email only. They enter their email and then enter the OTP sent on email to proceed.

#### Note: OTP length will be 4 digits

#### Personal Details Screen

#### The user logged in through email and OTP. It asked for two more details on the screen:

* #### name

* #### food preferences

#### The food preferences will have four options:

* #### vegetarian

* #### non-vegetarian

* #### everything

#### Note: In V1, name will be asked explicitly (no auto-fill from Google login).

#### Home page

#### They have the following components

* #### Create a recipe: An option to paste link and a CTA to generate recipe

  * #### Placeholder text: Paste Youtube video link to create a recipe

* #### My recipes: It will have a list of all recipes created by the user. Limit to first 5 recipes with a View more button. Each recipe will have an image, a name, name of the creator (sourced from Youtube) whose video is used

* #### 

* #### At the bottom, show the recipe currently being cooked. On clicking directly open the recipe at the same step

* #### Search existing recipe option (V1 scope: search only within the user’s own created recipes): Users can search for an existing recipe if they don’t want to create a new one.

  * #### Search works only on recipe names in the user’s own library (case-insensitive partial match).

  * #### No search results: Say No recipe found, search it on Youtube and paste a link to create one

#### Empty state

#### This state will show the capability of the product.

* #### Create a recipe with a Youtube video link

  * #### Paste the link and press the button

  * #### Your recipe will be generated within a few seconds

* #### Search for a recipe that you can cook on gas stove. No more pauses and resume and struggles to figure out the ingredients

#### Profile Page

* #### Name

* #### Email

* #### Add Phone number option

* #### An avatar (can be changed if needed)

* #### My Creations

  * #### List of all the recipes created by the user (paginate in groups of 10 for faster loading)

    * #### Name

    * #### An image

    * #### Name of video where its taken from

  * #### Order the list by placing the last created at the top

* #### Option to logout

* #### App version

* #### 

#### Recipe Creation Flow

* #### A placeholder for pasting the link

* #### A CTA to initiate the recipe creation

* #### A progress bar to show the progress (not actual but estimated)

* #### Show what’s being currently done in a user friendly manner like, extracting the video, transcribing video, creating list of ingredients, creating cooking steps

* #### Once created take the user to recipe page

* #### V1 simplification: Recipe creation happens on the creation flow screen. User should not exit the creation mid-way (no bottom fixed bar status tracking in V1).

* #### Steps: extract audio/video → transcript → ingredient extraction → step extraction → timing inference → image generation (optional)

  * #### If any of these fails once, retry again. If anything fails twice the whole creation should fail and an error should be thrown saying, Recipe could not be created for this video. Try with a different

#### Recipe Page

#### It will have the following components

* #### A header card

  * #### It will have CTAs for

    * #### Ingredients: On clicking, show a list of ingredients with respective quantities. (V1: no ingredient thumbnails/images.)

      * #### Each ingredient will also have their prep method(if any prep is involved)

      * #### e.g \- Onion \- 2 large or 100 grams \- finely chopped

    * #### Portion size: As per the video (by default 2 if its not specified in the video)

    * #### YT video link: can be an icon to redirect

    * #### Cooking time: Approx time for cooking, derived from the video (or sum of all the cooking time for each step)

    * #### Preparation: Show a list of preparation required

    * #### Start Recipe CTA

* #### On scrolling down it will take user to steps. Each step will be in the form of expandable cards

  * #### Step 1: Chop onion, garlic and tomatoes

    * #### On expanding it will show the quantities, the chopping type (finely chopped for onion, grating for garlic, etc.)

  * #### Step 2: Put oil in a pan and heat

    * #### On expanding it should show how much oil to heat, till what time and flame(high/low/medium) it should be heat, etc.

  * #### Step 3: Pressure Rajma

  * #### Step n: Garnish with dhaniya

#### Recipe in cooking mode

#### When the user clicks on start button, the recipe goes into cooking mode. The system will start tracking the progress in this mode and start giving reminders.

* #### On completion of a prep step (where nothing is cooked like cutting onion), there will be a CTA to mark this as done, the card will gray out and collapse on marking it as done with a green tick to reflect its done

* #### On starting a cooking step like heat oil for 30 seconds on high flame, the timer would start and remind on completion with completion sound

  * #### It will trigger a sound and notification on completion of the timer

#### State machine

* #### Not started → in progress → paused → completed

* #### Step states: not started / active / completed / skipped

* #### Can steps be skipped/unskipped \- Yes it can be skipped

#### States

* #### Started: When the user clicks on the start button

* #### Completed: When user clicks on the last button of recipe or 24 hours after the starte

* #### When user starts a new recipe: End the previous one

#### Timers

* #### Each step will have a single timer- Prep will be a different step. Timer will only run where heating is required on gas stove

* #### What happens if app is backgrounded or phone locked?

* #### Sound \+ notification: do you require notification permission? fallback behavior if denied?

## Edge Cases/Error Scenario

* #### Link not valid: Show an error saying, the link is broken or invalid. Paste the correct link. Show error on pressing CTA only. Playlist or timed link should not be considered

* #### No internet: Show a page with no internet showing an image (of no internet) and say that No network found (or a similar meaningful message

* #### Recipe not found:

#### Show a message with an image saying that we could not be found would have two CTAs below it:

* #### Refresh

* #### Go back

* #### Wrong OTP: Short message at the OTP screen saying "Wrong OTP entered. Please check the OTP again."

## Clarifying questions

* #### You mention user may exit; do they also cancel? If they “exit”, does job continue in background?

  * #### Yes, it continues on opening app but users should have option to cancel mid way. On pressing cancel, the process should stop

* #### If recipe exists: do you show existing recipe immediately and skip generation, or ask user to confirm?

  * #### Show immediately

* #### “Unique video link” rule: define canonicalization:

  * #### remove tracking params, normalize [youtu.be](http://youtu.be) vs [youtube.com](http://youtube.com), ignore timestamp?

  * #### Yes, do all of the above

* #### Do you store transcript? If yes, where and for how long? (execution/privacy) \- No need to store

* #### Can user edit the generated recipe (fix ingredients/steps) or is it read-only?

  * #### No editing allowed

* #### Do you show ingredient thumbnails: from where? (static ingredient image library vs generated vs none in v1)

  * #### V1: no ingredient thumbnails/images

* #### Do you want a “Next step” flow (auto-advance) or manual selection \- User will have to press next each time to advance to next step

* #### If user loses network mid-cooking mode, should the recipe still be usable offline

  * #### V1 simplification: generation requires internet, but once a recipe is generated/opened it should be usable offline in cooking mode (show a non-blocking offline indicator if needed).

* #### How do seeded recipes differ from user-generated? (property flag)- Use a ‘platform recipe’ flag

* #### Regional roman names: which languages? (e.g., `aliases: [ "rajma", "raajma", "rajmah" ]`)

  * #### English

  * #### Hindi

  * #### Tamil

  * #### Telugu

  * #### Kannada

* #### 

## Notifications

* #### Ask for notification permission on home page

* #### To be sent only on completion of timer on the heating steps

## UI/UX Notes

* #### The product will be used in kitchen where the users may not interact with the mobile app a lot

* #### Make the interactions easy as the user may use the product with dirty/wet hands in the kicthen

* #### The error message should not be plain, use images/icons wherever possible

## Architectural decisions

* #### Each recipe will have a unique video link. If a user uses a video link for which the recipe is already available, directly show them the recipe already created instead of creating again.

  * #### Before creating a recipe search for the video link in database to check if the recipe already exists for the video

* #### Use a free tool to extract the information from the video

* #### Use a model which is cheapest for creating the recipe and images

* #### The product should work on both iOS and android. Choose stack accordingly

* #### The seeded content should be generated via a script and stored in the database

* #### Configurable data should be stored as env variables

* #### When limit in signup hits, the old users should be allowed to use the app, only new signups will be halted

* #### 

## Fraud Prevention

* #### Users can’t generate a recipe without loggin in

* #### A user can generate a maximum of 5 recipe per day. Make it configurable so that the number can be updated later. Show a meaningful error when the user exceeds this limit

Done till 4.2 
