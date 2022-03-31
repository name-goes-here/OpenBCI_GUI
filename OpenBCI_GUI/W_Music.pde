
////////////////////////////////////////////////////
//
//    W_template.pde (ie "Widget Template")
//
//    This is a Template Widget, intended to be used as a starting point for OpenBCI Community members that want to develop their own custom widgets!
//    Good luck! If you embark on this journey, please let us know. Your contributions are valuable to everyone!
//
//    Created by: Conor Russomanno, November 2016
//
///////////////////////////////////////////////////,

import org.apache.commons.lang3.ArrayUtils;
import org.apache.commons.lang3.tuple.Pair;

import brainflow.BrainFlowModelParams;
import brainflow.DataFilter;
import brainflow.MLModel;

import javax.sound.midi.*;

class W_Music extends Widget {

    //to see all core variables/methods of the Widget class, refer to Widget.pde
    //put your custom variables here...
    ControlP5 localCP5;
    Button blinkButton;
    Button internalButton;
    Button diatonicButton;
    Button quantizeButton;
    ControlP5 chordDropdowns;
    ControlP5 focusTextfields;

    // UI variables
    int column0, column1, column2, column3, column4;
    int row0, row1, row2, row3, row4, row5, row6, row7, row8;
    int[] uiColumns;
    int itemWidth = 96;
    private final float chordDropdownScaling = .35;

    int channelCount;
    int[] exgChannels;
    double[][] dataArray;
    private int[] activeChannels;
    private double metricPrediction = 0d;

    MLModel mlModel;
    FocusXLim xLimit = FocusXLim.TEN;
    FocusMetric focusMetric = FocusMetric.CONCENTRATION;
    FocusClassifier focusClassifier = FocusClassifier.REGRESSION;

    int testPadding = 3;

    private boolean musicOn = false;
    private boolean blinkMode = true; // Switch chords by blinking if true, else switch chords by focusing more or less
    private boolean diatonicMode = true; // Selectable chords are only from the selected key, else any chord is selectable
    private boolean internalMode = true; // If true, send noteOn/Off messages to the internal Java synthesizer. Else, send noteOn/Off messages to an external MIDI driver
    private boolean quantizedMode = false; // If true, change chords only on the first beat of every measure
    private boolean firstBlink = false;
    private boolean onFirstChord = false;

    public boolean focusMode(){
        return !blinkMode;
    }
    String[] metronomeOptions = new String[]{"None", "Sound", "Visual", "Sou+Vis"};
    int metronomeConfig = 2;
    int currentBeat = 0;

    int key = 0;    // 0 = C .... 11 = B
    int baseRootNote = 48;  // Root of the key of C ( midi note that is one octave under middle C)
    String[] keys = new String[]{"C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"};
    String[] keysWithNone = new String[]{"None", "C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"};
    String[] fourths = new String[]{"F", "F#", "G", "Ab", "A", "Bb", "B", "C", "Db", "D", "Eb", "E"};
    String[] chords = new String[]{"I", "ii", "iii", "IV", "V", "vi", "vii\u00B0"};
    String[] chordsWithNone = new String[]{"None", "I", "ii", "iii", "IV", "V", "vi", "vii\u00B0"};

    ArrayList<ScrollableList> chordSequenceOne = new ArrayList<>(); // First blink sequence
    String[] chordSequenceOneNames = new String[]{"chordOne", "chordTwo", "chordThree", "chordFour", "chordFive"};
    ChordSequence sequenceOne;
    ArrayList<ScrollableList> chordSequenceTwo = new ArrayList<>(); // Second blink sequence
    String[] chordSequenceTwoNames = new String[]{"chordSix", "chordSeven", "chordEight", "chordNine", "chordTen"};
    ChordSequence sequenceTwo;
    ChordSequence currentSequence;

    int sequenceIndicatorRow;
    int chordIndicatorColumn;

    ArrayList<ScrollableList> chordSequenceThree = new ArrayList<>(); // Focus sequence
    String[] chordSequenceThreeNames = new String[]{"chordEleven", "chordTwelve", "chordThirteen", "chordFourteen", "chordFifteen"};
    ChordSequence sequenceThree;
    ArrayList<Textfield> focusRangeDivFields = new ArrayList<>();
    String[] focusRangeDivNames = new String[]{"div1", "div2", "div3", "div4"};
    int textFieldWidth = 20;
    boolean[] activeFocusDivFields = new boolean[]{false, true, false, false}; // Active focus text fields (where you specify the focus cutoffs between chords)
    ArrayList<Float> focusRanges = new ArrayList<>();
    boolean[] onFocusChord; // Array of which chord is currently active in focus mode
    int idxFocusChord; // Index of the chord in onFocusChord which is currently true/active

    boolean[][] isMinor = new boolean[3][5]; // Array of which chords are minor; chord is major if false. [sequence number: 0-2][chord number in sequence: 0-4]
    ArrayList<ArrayList<Button>> majorMinorButtons = new ArrayList<>(); // Buttons to toggle major/minor for each chord
    int[] lockedMajMinButton = new int[]{-1, -1}; // Major minor button that has been individually locked due to associated dropdown being active
    ScrollableList openDropdown = null;

    /*boolean secondBlink = false;
    long firstBlinkTime;
    long secondBlinkTime;*/

    Stack<Integer> activeNotes = new Stack<>();

    Synthesizer synth = null;
    MidiChannel channel = null;
    Receiver receiver = null;
    MidiDevice device = null;
    private final String MIDI_DRIVER = "LoopBe";
    Metronome metronome;

    String[] instruments = new String[]{"Organ", "Strings", "Brass", "Synth Pad"};
    int instrument = 19; // 19 = Rock Organ, 49 = String Ensemble 1, 62 = Brass Section, 90 = Pad 2 (Warm)

    W_Music(PApplet _parent){
        super(_parent); //calls the parent CONSTRUCTOR method of Widget (DON'T REMOVE)
        
        initialize_UI();

        channelCount = currentBoard.getNumEXGChannels();
        exgChannels = currentBoard.getEXGChannels();
        dataArray = new double[channelCount][];
        activeChannels = new int[]{0, 1, 2, 3};

        initBrainFlowMetric();

        initSynthesizer();
        metronome = new Metronome();
    }

    public void update(){
        super.update(); //calls the parent update() method of Widget (DON'T REMOVE)

        // Set key
        //System.out.println(chordDropdowns.get(ScrollableList.class, "chordTwo").getValue());

        if (currentBoard.isStreaming()) {
            metricPrediction = updateFocusState();
            if(!musicOn){
                musicOn = true;
                println("----Music on----");
                if(quantizedMode){
                    int tempo = 60;
                    try {
                        tempo = Integer.parseInt(localCP5.get(Textfield.class, "tempo").getText());
                        if(tempo < 20 || tempo > 240){
                            tempo = 60;
                            localCP5.get(Textfield.class, "tempo").setText("60");
                        }
                    } catch(NumberFormatException e){
                        localCP5.get(Textfield.class, "tempo").setText("60");
                    }
                    metronome.start(tempo, metronomeConfig == 1 || metronomeConfig == 3);
                }
                if(blinkMode){
                    float[] chordSeqValues = new float[chordSequenceOne.size()];
                    for(int i = 0; i < chordSequenceOne.size(); i++){
                        chordSeqValues[i] = chordSequenceOne.get(i).getValue();
                        if(i > 1){
                            chordSeqValues[i] -= 1; // Offset for the chord because the third, fourth, fifth dropdowns have a "None" option first
                        }
                    }
                    sequenceOne = new ChordSequence(chordSeqValues, 1);
                    currentSequence = sequenceOne;

                    for(int i = 0; i < chordSequenceTwo.size(); i++){
                        chordSeqValues[i] = chordSequenceTwo.get(i).getValue();
                        if(i > 1){
                            chordSeqValues[i] -= 1; // Offset for the chord because the third, fourth, fifth dropdowns have a "None" option first
                        }
                    }
                    sequenceTwo = new ChordSequence(chordSeqValues, 2);
                } else {
                    validateFocusRanges();
                    float[] chordSeqValues = new float[chordSequenceThree.size()];
                    for(int i = 0; i < chordSequenceThree.size(); i++){
                        chordSeqValues[i] = chordSequenceThree.get(i).getValue();
                        if(i < 1 || i > 2){
                            chordSeqValues[i] -= 1; // Offset for the chord because the first, fourth, fifth dropdowns have a "None" option first
                        }
                    }
                    sequenceThree = new ChordSequence(chordSeqValues, 3);
                    currentSequence = sequenceThree;
                    focusRanges.clear();
                    focusRanges.add(0.0);
                    for(int i = 0; i < focusRangeDivFields.size(); i++){
                        String text = focusRangeDivFields.get(i).getText();
                        if(text.equals("-")){
                            continue;
                        }
                        focusRanges.add(Float.parseFloat(text)/100.0);
                    }
                    focusRanges.add(1.0);
                    onFocusChord = new boolean[focusRanges.size() - 1];
                    for(int i = 0; i < onFocusChord.length; i++){
                        if(metricPrediction <= focusRanges.get(i + 1)){
                            idxFocusChord = i;
                            onFocusChord[i] = true;
                            currentSequence.setCurrent(i);
                            if(diatonicMode){
                                playChord(baseRootNote + key, currentSequence.getCurrentChord());
                            } else {
                                if(isMinor[currentSequence.getSequenceNumber() - 1][currentSequence.getCurrent()]){
                                    playMinorChord(baseRootNote + currentSequence.getCurrentChord());
                                } else {
                                    playMajorChord(baseRootNote + currentSequence.getCurrentChord());
                                }
                            }
                            chordIndicatorColumn = uiColumns[currentSequence.getCurrent()];
                            break;
                        }
                    }
                }
                lockUI();
            }
            if(blinkMode){
                //Using Blinks
                if(BLINKED_HARD){
                    // Switch sequence on a hard blink
                    if(currentSequence == sequenceOne){
                        currentSequence = sequenceTwo;
                        sequenceIndicatorRow = row5;
                    } else {
                        currentSequence = sequenceOne;
                        sequenceIndicatorRow = row2;
                    }
                    currentSequence.resetToStart();
                }
                if(BLINKED || BLINKED_HARD){
                    // Play the next chord on any blink
                    int nextChord = currentSequence.getNext();
                    if(diatonicMode){
                        handleChord("", baseRootNote + key, nextChord, -1);
                    } else {
                        if(isMinor[currentSequence.getSequenceNumber() - 1][currentSequence.getCurrent()]){
                            handleChord("min", baseRootNote + nextChord, -1, -1);
                        } else {
                            handleChord("maj", baseRootNote + nextChord, -1, -1);
                        }
                    }
                    firstBlink = true;
                }
            } else {
                // Using Focus
                for(int i = 0; i < onFocusChord.length; i++){
                    if(!onFocusChord[i] && metricPrediction <= focusRanges.get(i + 1) && metricPrediction > focusRanges.get(i)){
                        if(!quantizedMode || (quantizedMode && !metronome.chordQueued())){
                            onFocusChord[idxFocusChord] = false;
                            int nextChord = idxFocusChord > i ? currentSequence.getPrev() : currentSequence.getNext();
                            if(diatonicMode){
                                handleChord("", baseRootNote + key, nextChord, i);
                            } else {
                                if(isMinor[currentSequence.getSequenceNumber() - 1][currentSequence.getCurrent()]){
                                    handleChord("min", baseRootNote + nextChord, -1, i);
                                } else {
                                    handleChord("maj", baseRootNote + nextChord, -1, i);
                                }
                            }
                        }
                    }
                }
            }
        } else if(musicOn) {
            musicOn = false;
            println("----Music off----");
            stopAllNotes();
            metronome.stop();
            unlockUI();
        } else {
            checkDropdownOverlap();
            firstBlink = false;
        }

        if(cp5_widget.get(CustomScrollableList.class, "ChangeInstrument").isInside()){
            localCP5.get(Button.class, "quantizeButton").lock();
            chordDropdowns.get(ScrollableList.class, chordSequenceOneNames[3]).lock();
            chordDropdowns.get(ScrollableList.class, chordSequenceTwoNames[3]).lock();
            chordDropdowns.get(ScrollableList.class, chordSequenceThreeNames[3]).lock();
        } else {
            localCP5.get(Button.class, "quantizeButton").unlock();
            chordDropdowns.get(ScrollableList.class, chordSequenceOneNames[3]).unlock();
            chordDropdowns.get(ScrollableList.class, chordSequenceTwoNames[3]).unlock();
            chordDropdowns.get(ScrollableList.class, chordSequenceThreeNames[3]).unlock();
        }

        if(cp5_widget.get(CustomScrollableList.class, "ChangeKey").isInside() || cp5_widget.get(CustomScrollableList.class, "ChangeMetronome").isInside()){
            chordDropdowns.get(ScrollableList.class, chordSequenceOneNames[4]).lock();
            chordDropdowns.get(ScrollableList.class, chordSequenceTwoNames[4]).lock();
            chordDropdowns.get(ScrollableList.class, chordSequenceThreeNames[4]).lock();
        } else {
            chordDropdowns.get(ScrollableList.class, chordSequenceOneNames[4]).unlock();
            chordDropdowns.get(ScrollableList.class, chordSequenceTwoNames[4]).unlock();
            chordDropdowns.get(ScrollableList.class, chordSequenceThreeNames[4]).unlock();
        }
    }

    private void handleChord(String type, int root, int quality, int focusIndex){
        if(quantizedMode){
            metronome.queueChord(type, root, quality, focusIndex);
        } else {
            if(type.equals("maj")){
                playMajorChord(root);
            } else if(type.equals("min")){
                playMinorChord(root);
            } else {
                playChord(root, quality);
            }
            if(!blinkMode){
                idxFocusChord = focusIndex;
                onFocusChord[focusIndex] = true;
            }
            chordIndicatorColumn = uiColumns[currentSequence.getCurrent()];
        }
    }

    public void playChord(int root, int quality){
        if(quality == 0){
            playMajorChord(root);
        } else if(quality == 1){
            playMinorChord(root + 2);
        } else if(quality == 2){
            playMinorChord(root + 4);
        } else if(quality == 3){
            playMajorChord(root + 5);
        } else if(quality == 4){
            playMajorChord(root + 7);
        } else if(quality == 5){
            playMinorChord(root + 9);
        } else {
            playDimChord(root + 11);
        }
    }

    public void playMajorChord(int root){
        stopAllNotes();
        if(internalMode){
            channel.noteOn(root, 100);
            channel.noteOn(root + 4, 100);
            channel.noteOn(root + 7, 100);
        } else {
            try {
                receiver.send(new ShortMessage(ShortMessage.NOTE_ON, 0, root, 100), -1);
                receiver.send(new ShortMessage(ShortMessage.NOTE_ON, 0, root + 4, 100), -1);
                receiver.send(new ShortMessage(ShortMessage.NOTE_ON, 0, root + 7, 100), -1);
            } catch (InvalidMidiDataException ex) {
                ex.printStackTrace();
            }
        }
        activeNotes.push(root);
        activeNotes.push(root + 4);
        activeNotes.push(root + 7);
    }

    public void playMinorChord(int root){
        stopAllNotes();
        if(internalMode){
            channel.noteOn(root, 100);
            channel.noteOn(root + 3, 100);
            channel.noteOn(root + 7, 100);
        } else {
            try {
                receiver.send(new ShortMessage(ShortMessage.NOTE_ON, 0, root, 100), -1);
                receiver.send(new ShortMessage(ShortMessage.NOTE_ON, 0, root + 3, 100), -1);
                receiver.send(new ShortMessage(ShortMessage.NOTE_ON, 0, root + 7, 100), -1);
            } catch (InvalidMidiDataException ex) {
                ex.printStackTrace();
            }
        }
        activeNotes.push(root);
        activeNotes.push(root + 3);
        activeNotes.push(root + 7);
    }

    public void playDimChord(int root){
        stopAllNotes();
        if(internalMode){
            channel.noteOn(root, 100);
            channel.noteOn(root + 3, 100);
            channel.noteOn(root + 6, 100);
        } else {
            try {
                receiver.send(new ShortMessage(ShortMessage.NOTE_ON, 0, root, 100), -1);
                receiver.send(new ShortMessage(ShortMessage.NOTE_ON, 0, root + 3, 100), -1);
                receiver.send(new ShortMessage(ShortMessage.NOTE_ON, 0, root + 6, 100), -1);
            } catch (InvalidMidiDataException ex) {
                ex.printStackTrace();
            }
        }
        activeNotes.push(root);
        activeNotes.push(root + 3);
        activeNotes.push(root + 6);
    }

    private void stopAllNotes(){
        while(activeNotes.size() > 0){
            if(internalMode){
                channel.noteOff(activeNotes.pop());
            } else {
                try {
                    receiver.send(new ShortMessage(ShortMessage.NOTE_OFF, 0, activeNotes.pop(), 100), -1);
                } catch (InvalidMidiDataException ex) {
                    ex.printStackTrace();
                }
            }
        }
    }

    void initialize_UI(){
        //This is the protocol for setting up dropdowns.
        //Note that these 3 dropdowns correspond to the 3 global functions below
        //You just need to make sure the "id" (the 1st String) has the same name as the corresponding function
        addDropdown("ChangeInstrument", "Instrument", Arrays.asList(instruments), 0);
        addDropdown("ChangeKey", "Key", Arrays.asList(keys), 0);
        //addDropdown("ChangeFirstChord", "Chord 1", Arrays.asList(chords), 0);
        //addDropdown("ChangeSecondChord", "Chord 2", Arrays.asList(chords), 3);
        addDropdown("ChangeMetronome", "Metronome ", Arrays.asList(metronomeOptions), 2);

        /*addDropdown("Dropdown5", "Drop 5", Arrays.asList("C", "D", "E"), 1);
        addDropdown("Dropdown6", "Drop 6", Arrays.asList("F", "G", "H", "I"), 3);*/

        //Instantiate local cp5 for this box. This allows extra control of drawing cp5 elements specifically inside this class.
        localCP5 = new ControlP5(ourApplet);
        localCP5.setGraphics(ourApplet, 0,0);
        localCP5.setAutoDraw(false);
        localCP5.addTextfield("tempo")
            .keepFocus(false)
            .setFont(h4)
            .setColorBackground(color(31,69,110))
            .setColorValueLabel(color(255))
            .setSize(textFieldWidth + 10, navH-4)
            .setAutoClear(false)
            .setCaptionLabel("");
            ;
        localCP5.get(Textfield.class, "tempo").setVisible(quantizedMode);

        chordDropdowns = new ControlP5(ourApplet);
        chordDropdowns.setGraphics(ourApplet, 0,0);
        chordDropdowns.setAutoDraw(false);

        focusTextfields = new ControlP5(ourApplet);
        focusTextfields.setGraphics(ourApplet, 0,0);
        focusTextfields.setAutoDraw(false);

        // Focus range div text boxes
        createTextField("div1");
        createTextField("div2");
        createTextField("div3");
        createTextField("div4");
        for(int i = 0; i < focusRangeDivNames.length; i++){
            focusRangeDivFields.add(focusTextfields.get(Textfield.class, focusRangeDivNames[i]));
        }
        int count = 1;
        for(int i = 0; i < 3; i++){
            ArrayList<Button> temp = new ArrayList<>();
            for(int j = 0; j < 5; j++){
                temp.add(createMajorMinorButton("button" + count++, i, j));
            }
            majorMinorButtons.add(temp);
        }

        // Blink mode dropdowns/chord sequences
        createDropdown("chordSix", Arrays.asList(chords), 4);
        createDropdown("chordSeven", Arrays.asList(chords), 5);
        setInactiveMajorMinorButtons(createDropdown("chordEight", Arrays.asList(chordsWithNone), 0), 1, 2);
        setInactiveMajorMinorButtons(createDropdown("chordNine", Arrays.asList(chordsWithNone), 0), 1, 3);
        setInactiveMajorMinorButtons(createDropdown("chordTen", Arrays.asList(chordsWithNone), 0), 1, 4);
        for(int i = 0; i < chordSequenceTwoNames.length; i++){
            chordSequenceTwo.add(chordDropdowns.get(ScrollableList.class, chordSequenceTwoNames[i]));
        }

        createDropdown("chordOne", Arrays.asList(chords), 0);
        createDropdown("chordTwo", Arrays.asList(chords), 3);
        setInactiveMajorMinorButtons(createDropdown("chordThree", Arrays.asList(chordsWithNone), 0), 0, 2);
        setInactiveMajorMinorButtons(createDropdown("chordFour", Arrays.asList(chordsWithNone), 0), 0, 3);
        setInactiveMajorMinorButtons(createDropdown("chordFive", Arrays.asList(chordsWithNone), 0), 0, 4);
        for(int i = 0; i < chordSequenceOneNames.length; i++){
            chordSequenceOne.add(chordDropdowns.get(ScrollableList.class, chordSequenceOneNames[i]));
        }

        // Focus mode dropdowns/chord sequences
        setInactiveMajorMinorButtons(setInactiveFocusTextFields(createDropdown("chordEleven", Arrays.asList(chordsWithNone), 0), 0), 2, 0);
        createDropdown("chordTwelve", Arrays.asList(chords), 0);
        createDropdown("chordThirteen", Arrays.asList(chords), 3);
        setInactiveMajorMinorButtons(setInactiveFocusTextFields(createDropdown("chordFourteen", Arrays.asList(chordsWithNone), 0), 2), 2, 3);
        setInactiveMajorMinorButtons(setInactiveFocusTextFields(createDropdown("chordFifteen", Arrays.asList(chordsWithNone), 0), 3), 2, 4);
        for(int i = 0; i < chordSequenceThreeNames.length; i++){
            chordSequenceThree.add(chordDropdowns.get(ScrollableList.class, chordSequenceThreeNames[i]));
        }

        createBlinkButton();
        showBlinkModeUI();
        createInternalButton();
        createDiatonicButton();
        createQuantizeButton();
        showDiatonicModeUI();
    }

    ScrollableList createDropdown(String name, List<String> items, int initialValue) {
        ScrollableList scrollList = new CustomScrollableList(chordDropdowns, name)
                .setOpen(false)
                //.setBarVisible(true)
                .setColorBackground(color(31,69,110)) // text field bg color
                .setColorValueLabel(color(255))       // text color
                .setColorCaptionLabel(color(255))
                .setColorForeground(color(125))    // border color when not selected
                .setColorActive(BUTTON_PRESSED)       // border color when selected
                // .setColorCursor(color(26,26,26))

                .setSize(itemWidth,(items.size()+1)*(navH-4))// + maxFreqList.size())
                .setBarHeight(navH-4) //height of top/primary bar
                .setItemHeight(navH-4) //height of all item/dropdown bars
                .addItems(items) // used to be .addItems(maxFreqList)
                .setVisible(false)
                .setValue(initialValue)
                ;
        chordDropdowns.getController(name)
            .getCaptionLabel() //the caption label is the text object in the primary bar
            .toUpperCase(false) //DO NOT AUTOSET TO UPPERCASE!!!
            .setText(items.get(initialValue))
            .setFont(h4)
            .setSize(14)
            .getStyle() //need to grab style before affecting the paddingTop
            .setPaddingTop(4)
            ;
        chordDropdowns.getController(name)
            .getValueLabel() //the value label is connected to the text objects in the dropdown item bars
            .toUpperCase(false) //DO NOT AUTOSET TO UPPERCASE!!!
            .setText(items.get(initialValue))
            .setFont(h5)
            .setSize(12) //set the font size of the item bars to 14pt
            .getStyle() //need to grab style before affecting the paddingTop
            .setPaddingTop(3) //4-pixel vertical offset to center text
            ;
        return scrollList;
    }

    ScrollableList setInactiveFocusTextFields(ScrollableList dropdown, int idx){
        lockUIcomponent(focusRangeDivFields.get(idx).setText("-"));
        dropdown.onChange(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) {
                if(dropdown.getValue() == 0){
                    focusRangeDivFields.get(idx).setText("-");
                    lockUIcomponent(focusRangeDivFields.get(idx));
                    resetFocusRanges();
                    activeFocusDivFields[idx] = false;
                } else {
                    unlockUIcomponent(focusRangeDivFields.get(idx));
                    activeFocusDivFields[idx] = true;
                }
            }
        });
        return dropdown;
    }

    void createTextField(String name){
        focusTextfields.addTextfield(name)
            .keepFocus(false)
            .setFont(h4)
            .setColorBackground(color(31,69,110))
            .setColorValueLabel(color(255))
            .setSize(textFieldWidth, navH-4)
            .setAutoClear(false)
            .setCaptionLabel("");
            ;
    }

    public void draw(){
        super.draw(); //calls the parent draw() method of Widget (DON'T REMOVE)

        //remember to refer to x,y,w,h which are the positioning variables of the Widget class
        //text("x", (polarWindowX+polarWindowWidth/2)+8, polarWindowY-5);
        /*textAlign(LEFT,CENTER);
        textFont(h1,20);
        fill(ACCEL_X_COLOR);
        if(currentBoard.isStreaming() && !blinkMode){
            text("Concentration = " + metricPrediction, x+testPadding , y + (h/12)*1.5 - 5);
        } else {
            text("Concentration = 0.000", x+testPadding , y + (h/12)*1.5 - 5);
        }
        fill(ACCEL_Y_COLOR);
        
        if(blinkMode){
            text("Current mode: Blink", x+testPadding, y + (h/12)*3 - 5);
        } else {
            text("Current mode: Focus", x+testPadding, y + (h/12)*3 - 5);
        }
        fill(ACCEL_Z_COLOR);
        if(!musicOn){
            text("Current chord: None", x+testPadding, y + (h/12)*4.5 - 5);
        } else {
            if(onFirstChord){
                text("Current chord: " + keys[key] + " Major", x+testPadding, y + (h/12)*4.5 - 5);
            } else {
                text("Current chord: " + fourths[key] + " Major", x+testPadding, y + (h/12)*4.5 - 5);
            }
        }*/

        textFont(h1,36);
        fill(color(31,69,110));
        if(currentBoard.isStreaming()){
            if(!blinkMode || firstBlink){
                text("*", chordIndicatorColumn + itemWidth/2 - itemWidth/12, sequenceIndicatorRow);
            }
        }
        textFont(h1,20);
        if(!blinkMode){
            text("|", column0 - 2, row5);
            text("Focus level", column2 - 5, row5);
            text("|", column4 + itemWidth - 2, row5);
            int rowFiveHalf = row5 + 25;
            text("0", column0 - 6, rowFiveHalf);
            if(currentBoard.isStreaming()){
                text((int) Math.floor(metricPrediction*100), column2 + itemWidth/2 - 7, rowFiveHalf);
            } else {
                text("-", column2 + itemWidth/2 - 2, rowFiveHalf);
            }
            text("100", column4 + itemWidth - 17, rowFiveHalf);
        }
        textFont(h1,16);
        if(quantizedMode){
            text("Tempo:", column0 - 5, row8 + (row8 - row7)/2);
            if(currentBeat > 0 && metronomeConfig > 1){
                text("Beat: " + currentBeat, column1, row8 + (row8 - row7)/2);
            }
        }

        //This draws all cp5 objects in the local instance
        localCP5.draw();
        chordDropdowns.draw();
        focusTextfields.draw();
    }

    public void screenResized(){
        super.screenResized(); //calls the parent screenResized() method of Widget (DON'T REMOVE)

        //Very important to allow users to interact with objects after app resize        
        localCP5.setGraphics(ourApplet, 0, 0);
        chordDropdowns.setGraphics(ourApplet, 0,0);
        focusTextfields.setGraphics(ourApplet, 0,0);

        column0 = x+w/22-12;
        int widthd = 46;//This value has been fine-tuned to look proper in windowed mode 1024*768 and fullscreen on 1920x1080
        column1 = x+12*w/widthd-25;//This value has been fine-tuned to look proper in windowed mode 1024*768 and fullscreen on 1920x1080
        column2 = x+(12+9*1)*w/widthd-25;
        column3 = x+(12+9*2)*w/widthd-25;
        column4 = x+(12+9*3)*w/widthd-25;
        row0 = y+0*h/10;
        row1 = y+1*h/10;
        row2 = y+2*h/10+h/15;
        row3 = y+3*h/10;
        row4 = y+4*h/10;
        row5 = y+5*h/10+h/15;
        row6 = y+6*h/10;
        row7 = y+7*h/10;
        row8 = y+8*h/10;
        int offset = 15;//This value has been fine-tuned to look proper in windowed mode 1024*768 and fullscreen on 1920x1080
        uiColumns = new int[]{column0, column1, column2, column3, column4};
        sequenceIndicatorRow = row2;
        chordIndicatorColumn = column0;

        int dropdownsItemsToShow = int((this.h0 * chordDropdownScaling) / (this.navH - 4));
        int dropdownHeight = (dropdownsItemsToShow + 1) * (this.navH - 4);
        int maxDropdownHeight = (settings.nwDataTypesArray.length + 1) * (this.navH - 4);
        if (dropdownHeight > maxDropdownHeight){
            dropdownHeight = maxDropdownHeight;
        }
        int majMinButtonOffset = navH-4;
        for(int i = 0; i < chordSequenceOne.size(); i++){
            chordSequenceOne.get(i).setSize(itemWidth, dropdownHeight);
            chordSequenceOne.get(i).setPosition(uiColumns[i], row3 - offset);
            majorMinorButtons.get(0).get(i).setPosition(uiColumns[i], row3 - offset + majMinButtonOffset);
        }
        for(int i = 0; i < chordSequenceTwo.size(); i++){
            chordSequenceTwo.get(i).setSize(itemWidth, dropdownHeight);
            chordSequenceTwo.get(i).setPosition(uiColumns[i], row6 - offset);
            majorMinorButtons.get(1).get(i).setPosition(uiColumns[i], row6 - offset + majMinButtonOffset);
        }
        for(int i = 0; i < chordSequenceThree.size(); i++){
            chordSequenceThree.get(i).setSize(itemWidth, dropdownHeight);
            chordSequenceThree.get(i).setPosition(uiColumns[i], row3 - offset);
            majorMinorButtons.get(2).get(i).setPosition(uiColumns[i], row3 - offset + majMinButtonOffset);
        }
        for(int i = 0; i < focusRangeDivFields.size(); i++){
            int endOfDropdown = uiColumns[i] + itemWidth;
            focusRangeDivFields.get(i).setPosition(endOfDropdown + (uiColumns[i + 1] - endOfDropdown)/2 - textFieldWidth/2, row4 - offset);
        }
        localCP5.get(Textfield.class, "tempo").setPosition(column0 + 55, row8);

        //We need to set the position of our Cp5 object after the screen is resized
        //widgetTemplateButton.setPosition(x + w/2 - widgetTemplateButton.getWidth()/2, y + h/2 - widgetTemplateButton.getHeight()/2);
        blinkButton.setPosition(column0, row0);
        internalButton.setPosition(column1, row0);
        diatonicButton.setPosition(column2, row0);
        quantizeButton.setPosition(column3, row0);
    }

    public void mousePressed(){
        super.mousePressed(); //calls the parent mousePressed() method of Widget (DON'T REMOVE)
        //Since GUI v5, these methods should not really be used.
        //Instead, use ControlP5 objects and callbacks. 
        //Example: createWidgetTemplateButton() found below
    }

    public void mouseReleased(){
        super.mouseReleased(); //calls the parent mouseReleased() method of Widget (DON'T REMOVE)
        //Since GUI v5, these methods should not really be used.
    }

    //When creating new UI objects, follow this rough pattern.
    //Using custom methods like this allows us to condense the code required to create new objects.
    //You can find more detailed examples in the Control Panel, where there are many UI objects with varying functionality.
    private void createBlinkButton() {
        //This is a generalized createButton method that allows us to save code by using a few patterns and method overloading
        blinkButton = createButton(localCP5, "blinkButton", "Blink mode", x + w/2, y + h/2, itemWidth, navHeight, p4, 12, colorNotPressed, OPENBCI_DARKBLUE);
        blinkButton.setDescription("Click to switch chords by focusing more or less");
        //Set the border color explicitely
        blinkButton.setBorderColor(OBJECT_BORDER_GREY);
        //For this button, only call the callback listener on mouse release
        blinkButton.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) {
                //If using a TopNav object, ignore interaction with widget object (ex. widgetTemplateButton)
                if (!topNav.configSelector.isVisible && !topNav.layoutSelector.isVisible) {
                    if(blinkMode){
                        blinkButton.getCaptionLabel().setText("Focus mode");
                        blinkButton.setDescription("Click to change chords by blinking, sequence by blinking hard");
                    } else {
                        blinkButton.getCaptionLabel().setText("Blink mode");
                        blinkButton.setDescription("Click to change chords by focusing more or less");
                    }
                    sequenceIndicatorRow = row2;
                    blinkMode = !blinkMode;
                    showBlinkModeUI();
                    showDiatonicModeUI();
                }
            }
        });
    }

    private void createInternalButton() {
        internalButton = createButton(localCP5, "internalButton", "Internal mode", x + w/2, y + h/2, itemWidth, navHeight, p4, 12, colorNotPressed, OPENBCI_DARKBLUE);
        internalButton.setDescription("Click to play chords on an external sythesizer");
        internalButton.setBorderColor(OBJECT_BORDER_GREY);
        internalButton.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) {
                if (!topNav.configSelector.isVisible && !topNav.layoutSelector.isVisible) {
                    if(internalMode){
                        internalButton.getCaptionLabel().setText("External mode");
                        internalButton.setDescription("Click to play chords on the internal synthesizer");
                    } else {
                        internalButton.getCaptionLabel().setText("Internal mode");
                        internalButton.setDescription("Click to play chords on an external sythesizer (send MIDI events to LoopBe1 MIDI driver)");
                    }
                    internalMode = !internalMode;
                }
            }
        });
    }

    private void createDiatonicButton() {
        //This is a generalized createButton method that allows us to save code by using a few patterns and method overloading
        diatonicButton = createButton(localCP5, "diatonicButton", "Diatonic mode", x + w/2, y + h/2, itemWidth, navHeight, p4, 12, colorNotPressed, OPENBCI_DARKBLUE);
        diatonicButton.setDescription("Click to choose chords from any key");
        //Set the border color explicitely
        diatonicButton.setBorderColor(OBJECT_BORDER_GREY);
        //For this button, only call the callback listener on mouse release
        diatonicButton.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) {
                //If using a TopNav object, ignore interaction with widget object (ex. widgetTemplateButton)
                if (!topNav.configSelector.isVisible && !topNav.layoutSelector.isVisible) {
                    if(diatonicMode){
                        diatonicButton.getCaptionLabel().setText("Chromatic mode");
                        diatonicButton.setDescription("Click to choose chords from the selected key");
                    } else {
                        diatonicButton.getCaptionLabel().setText("Diatonic mode");
                        diatonicButton.setDescription("Click to choose chords from any key");
                    }
                    diatonicMode = !diatonicMode;
                    setDropdownLists();
                    showDiatonicModeUI();
                }
            }
        });
    }

    private void createQuantizeButton() {
        quantizeButton = createButton(localCP5, "quantizeButton", "Free-form mode", x + w/2, y + h/2, itemWidth, navHeight, p4, 12, colorNotPressed, OPENBCI_DARKBLUE);
        quantizeButton.setDescription("Click to quantize chord changes to the first beat");
        quantizeButton.setBorderColor(OBJECT_BORDER_GREY);
        quantizeButton.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) {
                //If using a TopNav object, ignore interaction with widget object (ex. widgetTemplateButton)
                if (!topNav.configSelector.isVisible && !topNav.layoutSelector.isVisible) {
                    if(quantizedMode){
                        quantizeButton.getCaptionLabel().setText("Free-form mode");
                        quantizeButton.setDescription("Click to quantize chord changes to the first beat");
                    } else {
                        quantizeButton.getCaptionLabel().setText("Quantized mode");
                        quantizeButton.setDescription("Click to change chords regardless of timing");
                    }
                    quantizedMode = !quantizedMode;
                    localCP5.get(Textfield.class, "tempo").setVisible(quantizedMode);
                }
            }
        });
    }

    private Button createMajorMinorButton(String name, int sequence, int chord) {
        Button majorMinorButton = createButton(localCP5, name, "Major", x + w/2, y + h/2, itemWidth - 1, navHeight, p4, 12, colorNotPressed, OPENBCI_DARKBLUE);
        majorMinorButton.setDescription("Click to make chord minor");
        majorMinorButton.setBorderColor(OBJECT_BORDER_GREY);
        majorMinorButton.setVisible(false);
        majorMinorButton.onRelease(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) {
                //If using a TopNav object, ignore interaction with widget object (ex. widgetTemplateButton)
                if (!topNav.configSelector.isVisible && !topNav.layoutSelector.isVisible) {
                    if(isMinor[sequence][chord]){
                        majorMinorButton.getCaptionLabel().setText("Major");
                        majorMinorButton.setDescription("Click to make chord minor");
                    } else {
                        majorMinorButton.getCaptionLabel().setText("Minor");
                        majorMinorButton.setDescription("Click to make chord major");
                    }
                    isMinor[sequence][chord] = !isMinor[sequence][chord];
                }
            }
        });
        return majorMinorButton;
    }

    ScrollableList setInactiveMajorMinorButtons(ScrollableList dropdown, int i, int j){
        majorMinorButtons.get(i).get(j).getCaptionLabel().setText("-");
        lockUIcomponent(majorMinorButtons.get(i).get(j));
        dropdown.onChange(new CallbackListener() {
            public void controlEvent(CallbackEvent theEvent) {
                if(dropdown.getValue() == 0){
                    majorMinorButtons.get(i).get(j).getCaptionLabel().setText("-");
                    lockUIcomponent(majorMinorButtons.get(i).get(j));
                } else {
                    majorMinorButtons.get(i).get(j).getCaptionLabel().setText("Major");
                    unlockUIcomponent(majorMinorButtons.get(i).get(j));
                    isMinor[i][j] = false;
                }
            }
        });
        return dropdown;
    }

    void setDropdownLists(){
        ArrayList<List<String>> items = new ArrayList<>();
        if(diatonicMode){
            items.add(Arrays.asList(chordsWithNone));
            items.add(Arrays.asList(chords));
        } else {
            items.add(Arrays.asList(keysWithNone));
            items.add(Arrays.asList(keys));
        }
        chordSequenceOne.get(0).setItems(items.get(1))
            .setValue(0);
        chordSequenceTwo.get(0).setItems(items.get(1))
            .setValue(4);
        chordSequenceOne.get(1).setItems(items.get(1))
            .setValue(3);
        chordSequenceTwo.get(1).setItems(items.get(1))
            .setValue(5);
        for(int i = 2; i < chordSequenceOne.size(); i++){
            chordSequenceOne.get(i).setItems(items.get(0))
                .setValue(0);
            chordSequenceTwo.get(i).setItems(items.get(0))
                .setValue(0);
        }
        chordSequenceThree.get(1).setItems(items.get(1))
            .setValue(0);
        chordSequenceThree.get(2).setItems(items.get(1))
            .setValue(3);
        chordSequenceThree.get(0).setItems(items.get(0))
            .setValue(0);
        chordSequenceThree.get(3).setItems(items.get(0))
            .setValue(0);
        chordSequenceThree.get(4).setItems(items.get(0))
            .setValue(0);
    }

    boolean checkDropdownOverlap() {
        /*if(cp5_widget.get(NavBarDropdown.class, "ChangeKey").isInside()){
            localCP5.get(Button.class, "diatonicButton").lock();
        } else {
            localCP5.get(Button.class, "diatonicButton").unlock();
        }*/
        for(int i = 0; i < chordSequenceOne.size(); i++){
            if(chordSequenceOne.get(i).isOpen() && (!majorMinorButtons.get(0).get(i).isLock() || !majorMinorButtons.get(1).get(i).isLock())){
                return lockMajMinButton(chordSequenceOne.get(i), 0, i);
            }
        }
        for(int i = 0; i < chordSequenceTwo.size(); i++){
            if(chordSequenceTwo.get(i).isOpen() && !majorMinorButtons.get(1).get(i).isLock()){
                return lockMajMinButton(chordSequenceTwo.get(i), 1, i);
            }
        }
        for(int i = 0; i < chordSequenceThree.size(); i++){
            if(chordSequenceThree.get(i).isOpen() && !majorMinorButtons.get(2).get(i).isLock()){
                return lockMajMinButton(chordSequenceThree.get(i), 2, i);
            }
        }
        if(openDropdown == null){
            return false;
        }
        if(!openDropdown.isOpen() && lockedMajMinButton[0] > -1){
            if(openDropdown.getValue() != 0){
                majorMinorButtons.get(lockedMajMinButton[0]).get(lockedMajMinButton[1]).unlock();
            }
            if(lockedMajMinButton[0] == 0){
                majorMinorButtons.get(lockedMajMinButton[0] + 1).get(lockedMajMinButton[1]).unlock();
            }
            lockedMajMinButton[0] = -1;
            lockedMajMinButton[1] = -1;
        }
        return false;
    }

    boolean lockMajMinButton(ScrollableList dropdown, int i, int j){
        lockedMajMinButton[0] = i;
        lockedMajMinButton[1] = j;
        majorMinorButtons.get(lockedMajMinButton[0]).get(lockedMajMinButton[1]).lock();
        if(lockedMajMinButton[0] == 0){
            majorMinorButtons.get(lockedMajMinButton[0] + 1).get(lockedMajMinButton[1]).lock();
        }
        openDropdown = dropdown;
        return true;
    }

    void validateFocusRanges(){
        boolean needsReset = false;
        int prev = Integer.MIN_VALUE;
        for(int i = 0; i < focusRangeDivFields.size(); i++){
            if(!focusRangeDivFields.get(i).isLock()){
                if(needsReset){
                    continue;
                }
                String text = focusRangeDivFields.get(i).getText();
                if(!isNumeric(text)){
                    needsReset = true;
                    continue;
                }
                int num = Integer.parseInt(text);
                if(num < 1 || num > 99 || num <= prev){
                    needsReset = true;
                    continue;
                }
                prev = num;
            }
        }
        if(needsReset){
            resetFocusRanges();
        }
    }

    boolean isNumeric(String str) {
        if (str == null) {
            return false;
        }
        try {
            int i = Integer.parseInt(str);
        } catch (NumberFormatException nfe) {
            return false;
        }
        return true;
    }

    void resetFocusRanges(){
        Stack<Integer> activeIdxs = new Stack<>();
        for(int i = 0; i < focusRangeDivFields.size(); i++){
            if(!focusRangeDivFields.get(i).isLock()){
                activeIdxs.add(i);
            }
        }
        int numActiveChords = activeIdxs.size() + 1;
        int count = activeIdxs.size();
        while(!activeIdxs.isEmpty()){
            focusRangeDivFields.get(activeIdxs.pop()).setText(((100/numActiveChords) * count--) + "");
        }
    }

    void showBlinkModeUI(){
        for(int i = 0; i < chordSequenceOne.size(); i++){
            chordSequenceOne.get(i).setVisible(blinkMode);
        }
        for(int i = 0; i < chordSequenceTwo.size(); i++){
            chordSequenceTwo.get(i).setVisible(blinkMode);
        }
        for(int i = 0; i < chordSequenceThree.size(); i++){
            chordSequenceThree.get(i).setVisible(!blinkMode);
        }
        for(int i = 0; i < focusRangeDivFields.size(); i++){
            focusRangeDivFields.get(i).setVisible(!blinkMode);
        }
    }

    void showDiatonicModeUI(){
        for(int i = 0; i < 2; i++){
            for(int j = 0; j < majorMinorButtons.get(i).size(); j++){
                majorMinorButtons.get(i).get(j).setVisible(!diatonicMode && blinkMode);
            }
        }
        for(int i = 0; i < majorMinorButtons.get(2).size(); i++){
            majorMinorButtons.get(2).get(i).setVisible(!diatonicMode && !blinkMode);
        }
    }

    void lockUI(){
        cp5_widget.get(CustomScrollableList.class, "ChangeInstrument").lock().setColorBackground(BUTTON_LOCKED_GREY);
        cp5_widget.get(CustomScrollableList.class, "ChangeKey").lock().setColorBackground(BUTTON_LOCKED_GREY);
        cp5_widget.get(CustomScrollableList.class, "ChangeMetronome").lock().setColorBackground(BUTTON_LOCKED_GREY);
        lockUIcomponent(blinkButton);
        lockUIcomponent(internalButton);
        lockUIcomponent(diatonicButton);
        lockUIcomponent(quantizeButton);
        if(blinkMode){
            for(int i = 0; i < chordSequenceOne.size(); i++){
                lockUIcomponent(chordSequenceOne.get(i));
            }
            for(int i = 0; i < chordSequenceTwo.size(); i++){
                lockUIcomponent(chordSequenceTwo.get(i));
            }
        } else {
            for(int i = 0; i < chordSequenceThree.size(); i++){
                lockUIcomponent(chordSequenceThree.get(i));
            }
            for(int i = 0; i < activeFocusDivFields.length; i++){
                if(activeFocusDivFields[i]){
                    lockUIcomponent(focusRangeDivFields.get(i));
                }
            }
        }
        if(!diatonicMode){
            for(int i = 0; i < majorMinorButtons.size(); i++){
                for(int j = 0; j < majorMinorButtons.get(i).size(); j++){
                    if(!majorMinorButtons.get(i).get(j).getCaptionLabel().getText().equals("-")){
                        lockUIcomponent(majorMinorButtons.get(i).get(j));
                    }
                }
            }
        }
    }

    void lockUIcomponent(Button button){
        button.setColorBackground(BUTTON_LOCKED_GREY)
            .lock();
    }

    void lockUIcomponent(ScrollableList list){
        list.setColorBackground(color(69, 114, 163))
            .lock();
    }

    void lockUIcomponent(Textfield field){
        field.setColorBackground(color(69, 114, 163))
            .lock();
    }

    void unlockUI(){
        cp5_widget.get(CustomScrollableList.class, "ChangeInstrument").unlock().setColorBackground(colorNotPressed);
        cp5_widget.get(CustomScrollableList.class, "ChangeKey").unlock().setColorBackground(colorNotPressed);
        cp5_widget.get(CustomScrollableList.class, "ChangeMetronome").unlock().setColorBackground(colorNotPressed);
        unlockUIcomponent(blinkButton);
        unlockUIcomponent(internalButton);
        unlockUIcomponent(diatonicButton);
        unlockUIcomponent(quantizeButton);
        if(blinkMode){
            for(int i = 0; i < chordSequenceOne.size(); i++){
                unlockUIcomponent(chordSequenceOne.get(i));
            }
            for(int i = 0; i < chordSequenceTwo.size(); i++){
                unlockUIcomponent(chordSequenceTwo.get(i));
            }
        } else {
            for(int i = 0; i < chordSequenceThree.size(); i++){
                unlockUIcomponent(chordSequenceThree.get(i));
            }
            for(int i = 0; i < activeFocusDivFields.length; i++){
                if(activeFocusDivFields[i]){
                    unlockUIcomponent(focusRangeDivFields.get(i));
                }
            }
        }
        if(!diatonicMode){
            for(int i = 0; i < majorMinorButtons.size(); i++){
                for(int j = 0; j < majorMinorButtons.get(i).size(); j++){
                    if(!majorMinorButtons.get(i).get(j).getCaptionLabel().getText().equals("-")){
                        unlockUIcomponent(majorMinorButtons.get(i).get(j));
                    }
                }
            }
        }
    }

    void unlockUIcomponent(Button button){
        button.setColorBackground(colorNotPressed)
            .unlock();
    }

    void unlockUIcomponent(ScrollableList list){
        list.setColorBackground(color(31,69,110))
            .unlock();
    }

    void unlockUIcomponent(Textfield field){
        field.setColorBackground(color(31,69,110))
            .unlock();
    }

    //Core method to fetch and process data
    //Returns a metric value from 0. to 1. When there is an error, returns -1.
    private double updateFocusState() {
        try {
            int windowSize = currentBoard.getSampleRate() * xLimit.getValue(); // Window size is 2000
            //println(windowSize + " = " + currentBoard.getSampleRate() + " * " + xLimit.getValue()); // 2000 = 200 * 10
            // getData in GUI returns data in shape ndatapoints x nchannels, in BrainFlow its transposed
            List<double[]> currentData = currentBoard.getData(windowSize);

            if (currentData.size() != windowSize || activeChannels.length <= 0) {
                return -1.0;
            }

            for (int i = 0; i < channelCount; i++) {
                dataArray[i] = new double[windowSize];
                for (int j = 0; j < currentData.size(); j++) {
                    dataArray[i][j] = currentData.get(j)[exgChannels[i]];
                }
            }

            //Full Source Code for this method: https://github.com/brainflow-dev/brainflow/blob/c5f0ad86683e6eab556e30965befb7c93e389a3b/src/data_handler/data_handler.cpp#L1115
            Pair<double[], double[]> bands = DataFilter.get_avg_band_powers (dataArray, activeChannels, currentBoard.getSampleRate(), true);
            double[] featureVector = ArrayUtils.addAll (bands.getLeft (), bands.getRight ());

            //Left array is Averages, right array is Standard Deviations. Update values using Averages.
            //updateBandPowerTableValues(bands.getLeft());

            //Keep this here
            double prediction = mlModel.predict(featureVector);
            //println("Concentration: " + prediction);

            //Send band power and prediction data to AuditoryNeurofeedback class
            //auditoryNeurofeedback.update(bands.getLeft(), (float)prediction);
            
            return prediction;

        } catch (BrainFlowError e) {
            e.printStackTrace();
            println("Error updating focus state!");
            return -1d;
        }
    }

    /*private void updateBandPowerTableValues(double[] bandPowers) {
        for (int i = 0; i < bandPowers.length; i++) {
            dataGrid.setString(df.format(bandPowers[i]), 1 + i, 1);
        }
    }*/

    private void initBrainFlowMetric() {
        BrainFlowModelParams modelParams = new BrainFlowModelParams(
                focusMetric.getMetric().get_code(),
                focusClassifier.getClassifier().get_code()
                );
        mlModel = new MLModel (modelParams);
        try {
            mlModel.prepare();
        } catch (BrainFlowError e) {
            e.printStackTrace();
        }
    }

    private void initSynthesizer() {
        try {
            // Initialize synthesizer for playing chords
            synth = MidiSystem.getSynthesizer();
            synth.open();
            println("------Synth started------");
            channel = synth.getChannels()[0];
            channel.programChange(0, instrument);  // Change Channel 0 to current value of variable instrument

            // Initialize receiver for sending MIDI to external MIDI driver
            device = findLoopBe1();
            device.open();
            receiver = device.getReceiver();
        } catch(MidiUnavailableException e){
			e.printStackTrace();
		}
    }

    private MidiDevice findLoopBe1(){
        MidiDevice.Info[] devices = MidiSystem.getMidiDeviceInfo();
        for(int i = 0; i < devices.length; i++){
            if(devices[i].getName().startsWith(MIDI_DRIVER)){
                try {
                    MidiDevice device = MidiSystem.getMidiDevice(devices[i]);
                    if(device.getMaxReceivers() != 0){
                        return device;
                    }
                } catch (MidiUnavailableException e){
                    e.printStackTrace();
                }
            }
        }
        println("----LoopBe1 MIDI driver not found----");
        return null;
    }

    //Called on haltSystem() when GUI exits or session stops
    public void endSession() {
        try {
            mlModel.release();
        } catch (BrainFlowError e) {
            e.printStackTrace();
        }
        synth.close();
        device.close();
        metronome.stopSequencer();
    }

};

//These functions need to be global! These functions are activated when an item from the corresponding dropdown is selected
void ChangeKey(int n){
    w_music.key = n;
    println("Item " + (n+1) + " selected from the ChangeKey Dropdown");
    /*if(n==0){
        //do this
    } else if(n==1){
        //do this instead
    }*/
}

void ChangeInstrument(int n){
    // 19 = Rock Organ, 49 = String Ensemble 1, 62 = Brass Section, 90 = Pad 2 (Warm)
    if(n == 0){
        w_music.instrument = 19;
    } else if(n == 1){
        w_music.instrument = 49;
    } else if(n == 2){
        w_music.instrument = 62;
    } else if(n == 3){
        w_music.instrument = 90;
    }
    w_music.channel.programChange(0, w_music.instrument);
    println("Item " + (n+1) + " selected from the ChangeInstrument Dropdown");
}

void ChangeMetronome(int n){
    w_music.metronomeConfig = n;
}

void Dropdown6(int n){
    println("Item " + (n+1) + " selected from Dropdown 6");
}

class ChordSequence {
    private int[] chords; // -1 = None, 0 = Major one, 1 = minor 2nd ... 6 = diminished 7th
    private int current = -1;
    private int sequenceNumber;

    public ChordSequence(int[] chordsInOrder, int num){
        chords = new int[5];
        for(int i = 0; i < chordsInOrder.length; i++){
            chords[i] = chordsInOrder[i];
        }
        sequenceNumber = num;
    }

    public ChordSequence(float[] chordsInOrder, int num){
        chords = new int[5];
        for(int i = 0; i < chordsInOrder.length; i++){
            chords[i] = (int) chordsInOrder[i];
        }
        sequenceNumber = num;
    }

    public int getSequenceNumber(){
        return sequenceNumber;
    }

    public int getCurrent(){
        return current;
    }

    public int getCurrentChord(){
        return chords[current];
    }

    public void setCurrent(int c){
        Stack<Integer> activeChords = new Stack<>();
        for(int i = chords.length - 1; i >= 0; i--){
            if(chords[i] >= 0){
                activeChords.push(i);
            }
        }
        for(int i = 0; i < c; i++){
            activeChords.pop();
        }
        current = activeChords.pop();
    }
    
    public int getNext(){
        nextChord();
        while(chords[current] < 0){
            nextChord();
        }
        return chords[current];
    }

    private void nextChord(){
        current++;
        if(current == 5){
            current = 0;
        }
    }

    public int getPrev(){
        prevChord();
        while(chords[current] < 0){
            prevChord();
        }
        return chords[current];
    }

    private void prevChord(){
        current--;
        if(current == -1){
            current = 4;
        }
    }

    public void resetToStart(){
        current = -1;
    }
}

class Metronome implements MetaEventListener {
    private Sequencer sequencer;
    private int bpm;
    private Queue<int[]> chords;
    private int focusIdx;

    public Metronome(){
        chords = new LinkedList<>();
        try {
            openSequencer();
        } catch (MidiUnavailableException e) {
            println(e);
        }
    }

    public void queueChord(String type, int root, int quality, int focusIndex){
        if(chords.size() == 0){
            if(type.equals("maj")){
                chords.offer(new int[]{1, root});
            } else if(type.equals("min")){
                chords.offer(new int[]{2, root});
            } else {
                chords.offer(new int[]{0, root, quality});
            }
            focusIdx = focusIndex;
        }
    }

    public boolean chordQueued(){
        return chords.size() != 0;
    }

    public void start(int bpm, boolean audible) {
        try {
            this.bpm = bpm;
            startSequence(createSequence(audible));
        } catch (InvalidMidiDataException e) {
            println(e);
        }
    }

    public void stop(){
        if(sequencer.isRunning()){
            sequencer.stop();
            chords.clear();
            w_music.currentBeat = 0;
        }
    }

    private void openSequencer() throws MidiUnavailableException {
        sequencer = MidiSystem.getSequencer();
        sequencer.open();
        sequencer.addMetaEventListener(this);
    }

    public void stopSequencer(){
        sequencer.close();
    }

    private Sequence createSequence(boolean audible) {
        try {
            Sequence seq = new Sequence(Sequence.PPQ, 1);
            Track track = seq.createTrack();

            ShortMessage msg = new ShortMessage(ShortMessage.PROGRAM_CHANGE, 9, 1, 0);
            MidiEvent evt = new MidiEvent(msg, 0);
            track.add(evt);

            addNoteEvent(track, 0, audible);
            addNoteEvent(track, 1, audible);
            addNoteEvent(track, 2, audible);
            addNoteEvent(track, 3, audible);

            msg = new ShortMessage(ShortMessage.PROGRAM_CHANGE, 9, 1, 0);
            evt = new MidiEvent(msg, 4);
            track.add(evt);
            return seq;
        } catch (InvalidMidiDataException e) {
            println(e);
            return null;
        }
    }

    private void addNoteEvent(Track track, long tick, boolean on) throws InvalidMidiDataException {
        ShortMessage message = new ShortMessage(ShortMessage.NOTE_ON, 9, tick == 0 ? 76 : 77, on ? 127 : 0);
        MidiEvent event = new MidiEvent(message, tick);
        track.add(event);
        MetaMessage metaMessage = new MetaMessage();
		metaMessage.setMessage((int) tick, new byte[]{0}, 1);
        track.add(new MidiEvent((metaMessage), tick));
    }

    private void startSequence(Sequence seq) throws InvalidMidiDataException {
        sequencer.setSequence(seq);
        sequencer.setTempoInBPM(bpm);
        sequencer.start();
    }

    @Override
    public void meta(MetaMessage message) {
        w_music.currentBeat = message.getType() + 1;
        if(message.getType() == 0 && chords.size() != 0){
            int[] arr = chords.poll();
            if(arr[0] == 0){
                w_music.playChord(arr[1], arr[2]);
            } else if(arr[0] == 1){
                w_music.playMajorChord(arr[1]);
            } else if(arr[0] == 2){
                w_music.playMinorChord(arr[1]);
            }
            if(w_music.focusMode() && focusIdx > -1){
                w_music.idxFocusChord = focusIdx;
                w_music.onFocusChord[focusIdx] = true;
            }
            w_music.chordIndicatorColumn = w_music.uiColumns[w_music.currentSequence.getCurrent()];
        }
        if (message.getType() != 47) {  // 47 is end of track
            return;
        }
        doLoop();
    }

    private void doLoop() {
        if (sequencer == null || !sequencer.isOpen()) {
            return;
        }
        sequencer.setTickPosition(0);
        sequencer.start();
        sequencer.setTempoInBPM(bpm);
    }
}