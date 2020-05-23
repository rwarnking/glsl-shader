/**
 * Author: René Warnking
 * Copyright 2019 René Warnking
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

///////////////////////////////////////////////////
// Keybindings
///////////////////////////////////////////////////
const KEY_RESTART = 'KeyR';
const KEY_RIGHT = 'KeyD';
const KEY_LEFT = 'KeyA';
const KEY_DOWN = 'KeyS';
const KEY_FULLDOWN = 'Space';
const KEY_TLEFT = 'KeyQ';
const KEY_TRIGHT = 'KeyE';

///////////////////////////////////////////////////
// Setup
///////////////////////////////////////////////////
const width = 12;
if (width % 4 != 0)
    alert("Width should be 4 aligned");
const height = 20;
// TODO ?!
if (height % 2 != 0)
    alert("Height should be even");
let data = new Uint8Array(width * height);

// fill with random data (max 255)
for (let i = 0; i < height; i++) {
    for (let j = 0; j < width; j++) {
        //data[i * width + j] = Math.floor(Math.random() * Math.floor(255));
        data[i * width + j] = 0;
    }
}

const directions = Object.freeze({
    left: 0,
    right: 1,
    down: 2,
    downMax: 3
});

const rotations = Object.freeze({
    left: 0,
    right: 1
});

function isEmpty(pos) {
    return data[stone_pos_Y * width + pos] === 0;
}

const effect = {
    time: 0,
    direction: 1
};

///////////////////////////////////////////////////
// Uniforms
///////////////////////////////////////////////////
shaderboy.addUniform1i("uBoardTex", 0);
shaderboy.addUniform1f("uWidth", width);
shaderboy.addUniform1f("uHeight", height);
shaderboy.addUniform3fv("uCameraPos", [0.0, 0.0, 0.0]);
shaderboy.addUniform1f("uEffectTime", () => effect.time);

///////////////////////////////////////////////////
// Movement functions
///////////////////////////////////////////////////
function shiftStone(direction) {
    if (gameEnd)
        return;

	switch (direction) {
        case directions.left : {
            deleteStoneFromArray();
            stone_pos_X--;
            if (!checkIfAllowed()) {
            	stone_pos_X++;
            }
            addStoneToArray();
            break;
        }
        case directions.right : {
            deleteStoneFromArray();
            stone_pos_X++;
            if (!checkIfAllowed()) {
            	stone_pos_X--;
            }
            addStoneToArray();
            break;
        }
        case directions.down : {
            deleteStoneFromArray();
            stone_pos_Y--;
            if (!checkIfAllowed()) {
            	stone_pos_Y++;
            }
            addStoneToArray();
            break;
        }
        case directions.downMax : {
            deleteStoneFromArray();
            do {
            	stone_pos_Y--;
            } while(checkIfAllowed());
            stone_pos_Y++;
            addStoneToArray();
            t = speed;
            break;
        }
        default: break;
    }
}

// TODO objects can be rotated inside other ones - add corresponding checks
function rotateStone(rotate) {
    if (gameEnd)
        return;
    deleteStoneFromArray();

    let tmp = stoneArray;
    // TODO: in-place
    if (rotate == rotations.right) {
        let result = [];
        for (let i = 0; i < stoneArray[0].length; i++) {
            let row = stoneArray.map(e => e[i]).reverse();
            result.push(row);
        }
        stoneArray = result;
    } else if (rotate == rotations.left) {
        let result = [];
        for (let i = stoneArray[0].length-1; i >= 0; i--) {
            let row = stoneArray.map(e => e[i]);
            result.push(row);
        }
        stoneArray = result;
    }

    if (!checkIfAllowed()) {
		stoneArray = tmp;
    }
    addStoneToArray();
}

///////////////////////////////////////////////////
// Select the stone and fill up the Stone Array
///////////////////////////////////////////////////
const stoneArrayWidth = 4;
const stoneArrayHeight = 4;
//let stoneArray = new Uint8Array(stoneArrayWidth * stoneArrayHeight);
let stoneArray = [[]];

const stoneTypes = Object.freeze({
    size: 11,
    bar2: 0,
    bar3: 1,
    bar4: 2,
    J: 3,
    L: 4,
    cube: 5,
    smallL: 6,
    T: 7,
    plus: 8,
    S: 9,
    Z: 10
});

function fillWithRandomStone() {
    let stoneType = Math.floor(Math.random() * Math.floor(stoneTypes.size));
    stoneColor = Math.floor(Math.random() * Math.floor(254)) + 1;

    switch (stoneType) {
        case stoneTypes.bar2 : {
            stoneArray = [[stoneColor, stoneColor]];
            break;
        }
        case stoneTypes.bar3 : {
            stoneArray = [[stoneColor, stoneColor, stoneColor]];
            break;
        }
        case stoneTypes.bar4 : {
            stoneArray = [[stoneColor, stoneColor, stoneColor, stoneColor]];
            break;
        }
        case stoneTypes.J : {
            stoneArray = [
                [stoneColor, 0, 0],
                [stoneColor, stoneColor, stoneColor]
            ];
            break;
        }
        case stoneTypes.L : {
            stoneArray = [
                [stoneColor, stoneColor, stoneColor],
                [stoneColor, 0, 0]
            ];
            break;
        }
        case stoneTypes.cube : {
            stoneArray = [
                [stoneColor, stoneColor],
                [stoneColor, stoneColor]
            ];
            break;
        }
        case stoneTypes.smallL : {
            stoneArray = [
                [stoneColor, stoneColor],
                [stoneColor, 0]
            ];
            break;
        }
        case stoneTypes.T : {
            stoneArray = [
                [stoneColor, stoneColor, stoneColor],
                [0, stoneColor, 0]
            ];
            break;
        }
        case stoneTypes.plus : {
            stoneArray = [
                [0, stoneColor, 0],
                [stoneColor, stoneColor, stoneColor],
                [0, stoneColor, 0],
            ];
            break;
        }
        case stoneTypes.S : {
            stoneArray = [
                [0, stoneColor, stoneColor],
                [stoneColor, stoneColor, 0]
            ];
            break;
        }
        case stoneTypes.Z : {
            stoneArray = [
                [stoneColor, stoneColor, 0],
                [0, stoneColor, stoneColor]
            ];
            break;
        }
    }
}

function deleteStoneFromArray() {
    for (let y = 0; y < stoneArray.length; y++) {
        for (let x = 0; x < (stoneArray[y]).length; x++) {
            if (stoneArray[y][x] > 0) {
            	data[(stone_pos_Y - y) * width + stone_pos_X + x] = 0;
            }
        }
    }
}

function addStoneToArray() {
    for (let y = 0; y < stoneArray.length; y++) {
        for (let x = 0; x < (stoneArray[y]).length; x++) {
            if (stoneArray[y][x] > 0) {
            	data[(stone_pos_Y - y) * width + stone_pos_X + x] = stoneArray[y][x];
            }
        }
    }
}

///////////////////////////////////////////////////
// Rule-Check functions
///////////////////////////////////////////////////
function checkIfAllowed() {
    if (stone_pos_X + stoneArray[0].length > width ||
        stone_pos_X < 0 ||
        stone_pos_Y - stoneArray.length < 0
       )
        return false;

    for (let y = 0; y < stoneArray.length; y++) {
        for (let x = 0; x < (stoneArray[y]).length; x++) {
            if (stoneArray[y][x] > 0) {
            	if (data[(stone_pos_Y - y) * width + stone_pos_X + x] > 0)
                    return false;
            }
        }
    }
    return true;
}

// TODO is this method still necessary?
function checkBelowStone() {
    let result = true;
    // loop every column and check for lowest stone part to compare with field below
    // length should be the same for all arrays
    for (let x = 0; x < (stoneArray[0]).length; x++) {
    	let y = stoneArray.length - 1;
        for (; stoneArray[y][x] === 0; y--);

        // TODO shouldnt the first case be clear with one check, because there only
        // needs to be one entry in the last line
        if (stone_pos_Y - y - 1 === -1) {
            return false;
        } else if (
            data[(stone_pos_Y - y - 1) * width + stone_pos_X + x] > 0) {
        	return false;
        }
    }

	return result;
}

///////////////////////////////////////////////////
// Progress functions
///////////////////////////////////////////////////
function emitStone() {
    fillWithRandomStone();
	stone_pos_X = width / 2.0 - Math.round(stoneArray[0].length / 2.0);
    stone_pos_Y = height - 1;
}

let gameEnd = false;
function gameOver() {
    if (gameEnd)
        return gameEnd;
	for (let x = 0; x < width; x++) {
        if (data[(height - 1) * width + x] > 0) {
            gameEnd = true;
            return true;
        }
    }
    return false;
}

function clearLine(y) {
    for (let x = 0; x < width; x++) {
        data[y * width + x] = 0;
    }
}

function shiftLines(_y) {
    for (let y = _y; y < height - 1; y++) {
        for (let x = 0; x < width; x++) {
            data[y * width + x] = data[(y + 1) * width + x];
        }
    }
}

function ifLineCompleteDelete() {
    let count = speed;
    for (let y = 0; y < height; y++) {
        let x = 0;
        for ( ; x < width; x++) {
            if (data[y * width + x] === 0)
                break;
        }
        if (x == width) {
            shiftLines(y);
            y--;
            speed--;
        }
    }
    if (count - speed == 4)
        console.log("BOOM - Tetris for Jeff.");
}

///////////////////////////////////////////////////
// Effects (Background)
///////////////////////////////////////////////////
function updateEffect(minus) {
	effect.time += effect.direction * minus;

    if (effect.time <= -1) {
        effect.direction = 1;
        effect.time = -1 + minus;
    } else if (effect.time >= 1) {
        effect.direction = -1;
        effect.time = 1 - minus;
    }
}

///////////////////////////////////////////////////
// Initialize
///////////////////////////////////////////////////
let stone_pos_X = 0;
let stone_pos_Y = 0;
let t = 0;
let speed = 0;

function init(_speed = 40) {
    gameEnd = false;
    t = 0;
    // TODO Higher = slower
    speed = _speed;

    emitStone();
    addStoneToArray();
}

init();

///////////////////////////////////////////////////
// Callbacks
///////////////////////////////////////////////////
// For updating the stone position each interval
this.addFrameCallback(function(renderer, timestamp, time) {
    const minus = renderer.deltaTime * 0.01;
	updateEffect(minus);

    t += Math.round(renderer.deltaTime/0.016);
    if (t < speed) {
        return;
    }
    t = 0;

    if (checkBelowStone()) {
        deleteStoneFromArray();
        stone_pos_Y--;
        addStoneToArray();
    } else if (!gameOver()) {
        ifLineCompleteDelete();
        emitStone();
        addStoneToArray();
    } else {
        console.log("Game Over. You deleted " + (40 - speed) + " lines.");
        console.log("Press " + KEY_RESTART + " to restart.");
    }
});

///////////////////////////////////////////////////
// Parse Input
///////////////////////////////////////////////////
shaderboy.onKeyDown(function(event) {
    if (event.code == KEY_RESTART) {
        for (let y = 0; y < height; y++)
            clearLine(y);
        init();
    }

    if (gameEnd) {
        return;
    }
    // key actions
    switch (event.code) {
        case KEY_RIGHT:
            shiftStone(directions.right);
            AudioManager.play("woosh3");
            break;
        case KEY_LEFT:
            shiftStone(directions.left);
            AudioManager.play("woosh3");
            break;
        case KEY_DOWN:
            shiftStone(directions.down);
            AudioManager.play("woosh3");
            break;
        case KEY_FULLDOWN:
            shiftStone(directions.downMax);
            AudioManager.play("woosh1");
            break;
        case KEY_TLEFT:
            rotateStone(rotations.left);
            AudioManager.play("woosh2");
            break;
        case KEY_TRIGHT:
            rotateStone(rotations.right);
            AudioManager.play("woosh2");
            break;
    }
});

///////////////////////////////////////////////////
// Texture
///////////////////////////////////////////////////
const texture = this.gl().createTexture();

function addTexture(gl) {
    // Create a texture.
    gl.bindTexture(gl.TEXTURE_2D, texture);

    // fill texture with 3x2 pixels
    const level = 0;
    const internalFormat = gl.LUMINANCE;
    const border = 0;
    const format = gl.LUMINANCE;
    const type = gl.UNSIGNED_BYTE;

    const alignment = 4;
    gl.pixelStorei(gl.UNPACK_ALIGNMENT, alignment);

    gl.texImage2D(gl.TEXTURE_2D, level, internalFormat, width, height, border,
                  format, type, data);

    // set the filtering so we don't need mips and it's not filtered
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
}

addTexture(shaderboy.gl());

// Update Texture Data callback
this.addFrameCallback(function(renderer) {
    const gl = renderer.gl;
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.LUMINANCE, width, height, 0,
                  gl.LUMINANCE, gl.UNSIGNED_BYTE, data);
});
