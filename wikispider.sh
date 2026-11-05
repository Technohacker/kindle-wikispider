#!/bin/sh
# Name: WikiSpider
# Author: Kevin
# DontUseFBInk

TOUCH_WAIT_TIMEOUT=10
SUSPEND_DURATION=3600

# Show a message and wait for any touch input to exit the whole script
exit_on_touch() {
    fbink --wait -pmh -y -5 "Touch to exit"

    # event1 corresponds to the touchscreen on Kindle. Wait for at least a single byte to be read
    head -c1 /dev/input/event1 >> /dev/null && kill -SIGTERM "$$" &
    TOUCH_WAIT_PID=$!

    # Time-out if there's not been a touch event and just proceed as usual
    sleep $TOUCH_WAIT_TIMEOUT &
    wait -n

    kill $TOUCH_WAIT_PID | true >/dev/null 2>&1
}

# Put the Kindle to sleep and allow the user to exit if they need to
suspend_then_wait() {
    lipc-set-prop com.lab126.powerd preventScreenSaver 1
    rtcwake -s $SUSPEND_DURATION
    lipc-set-prop com.lab126.powerd preventScreenSaver 0
    exit_on_touch
}

# Previous and current page titles, starting from the main page
WIKI_PREVIOUS_PAGE_TITLE="Main_Page"
WIKI_PAGE_TITLE="Main_Page"

WIKI_API_URL="https://en.wikipedia.org/w/api.php"
WIKI_QUERY_CALL="${WIKI_API_URL}?action=query&format=json&formatversion=2&redirects=true"

WIKI_INFO_CALL="${WIKI_QUERY_CALL}&prop=info&inprop=url"
WIKI_SUMMARY_CALL="${WIKI_QUERY_CALL}&prop=extracts&exsentences=3&explaintext=true"
WIKI_IMAGE_CALL="${WIKI_QUERY_CALL}&prop=pageimages&piprop=original&pilimit=1&pilicense=any"
WIKI_LINKS_CALL="${WIKI_QUERY_CALL}&prop=links&pllimit=max&plnamespace=0"

QR_CALL="https://api.qrserver.com/v1/create-qr-code/?size=150x150&format=png"

# Select a random wiki link in the currently selected page
wiki_select() {
    for i in $(seq 1 10); do
        # Get all links from the current page
        LINKS_JSON=$(curl "${WIKI_LINKS_CALL}&titles=${WIKI_PAGE_TITLE}") || return 1
        LINKS_LEN=$(echo $LINKS_JSON | jq -r '.query.pages[0].links | length')

        # Make sure there's at least 1 link in it
        if [ $LINKS_LEN != "0" ]; then
            WIKI_PREVIOUS_PAGE_TITLE="$WIKI_PAGE_TITLE"
            WIKI_PAGE_TITLE=$(echo $LINKS_JSON | jq -r --argjson rand $RANDOM '.query.pages[0] | .links[$rand % (.links | length)] | .title | @uri' ) || return 1
            return 0
        fi

        # If not, try again with the previous page
        WIKI_PAGE_TITLE="$WIKI_PREVIOUS_PAGE_TITLE"
        sleep 5
    done

    exit 1
}

wiki_run() {
    INFO_JSON=$(curl "${WIKI_INFO_CALL}&titles=${WIKI_PAGE_TITLE}") || return 1
    SUMMARY_JSON=$(curl "${WIKI_SUMMARY_CALL}&titles=${WIKI_PAGE_TITLE}") || return 1
    IMAGE_JSON=$(curl "${WIKI_IMAGE_CALL}&titles=${WIKI_PAGE_TITLE}") || return 1

    page_title=$(echo $INFO_JSON | jq -r '.query.pages[0].title') || return 2
    page_url=$(echo $INFO_JSON | jq -r '.query.pages[0].fullurl') || return 2
    summary_text=$(echo $SUMMARY_JSON | jq -r '.query.pages[0].extract') || return 2
    image_url=$(echo $IMAGE_JSON | jq -r '.query.pages[0].original.source') || return 2

    echo $IMAGE_JSON
    image_data=$(curl $image_url | base64) || return 3

    qr_input_url=$(echo -n "${page_url}" | jq -sRr @uri)
    qr_data=$(curl "${QR_CALL}&data=${qr_input_url}" | base64) || return 3

    # Clear the screen first
    fbink \
        --wait \
        --clear \
        --flash

    # Show the title image without refreshing
    echo $image_data | base64 -d | fbink \
        --wait \
        --norefresh \
        --image file=-,halign=CENTER,valign=CENTER,w=840,h=0,y=-240
    unset image_data

    # Then the page title
    fbink \
        --wait \
        --norefresh \
        --truetype regular=/usr/java/lib/fonts/Futura-Medium.ttf,size=13,top=1000,bottom=-1060,left=120,right=300 \
        "$page_title"

    # And the page summary
    fbink \
        --wait \
        --norefresh \
        --truetype regular=/usr/java/lib/fonts/Futura-Medium.ttf,size=9,top=1100,bottom=120,left=120,right=300 \
        "$summary_text"

    # And the QR code off to the side
    echo $qr_data | base64 -d | fbink \
        --wait \
        --norefresh \
        --image file=-,halign=RIGHT,valign=BOTTOM,x=-120,y=-120
    unset qr_data

    # Then finally refresh the screen
    fbink \
        --wait \
        --refresh
}

while true; do
    wiki_select || exit 1
    wiki_run || exit 1

    suspend_then_wait
done
