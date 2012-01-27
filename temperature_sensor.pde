/*
 * Temperature Sensor - Print temperature from DS18B20 & LM35 to LCD
 * Reference: http://www.maxim-ic.com/datasheet/index.mvp/id/2812
 * Reference: http://www.national.com/mpf/LM/LM35.html
 *
 * Copyright (c) 2011, Anugrah Redja Kusuma <anugrah.redja@gmail.com>
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */
 
#include <LiquidCrystal.h>
#include <OneWire.h>
#include <DallasTemperature.h>

const int dsTempPin = 6;
const int lmTempPin = 5;
const int lightPin = 4;
const int tempSamples = 16; /* Number of samples to average from LM35 noisy output */
const int interval = 1000;  /* Update interval */

const int debounceDelay = 10;
const int buttonPins[] = { 8, 7 };
const int buttonCount = sizeof(buttonPins) / sizeof(int);

enum {
	CELCIUS,
	FAHRENHEIT,
	FIRST_MAX,
};

enum {
	TEMP2,
	LIGHT,
	TIMER,
	DELTA,
	SECOND_MAX,
};

int firstMode = CELCIUS;
int secondMode = TEMP2;

unsigned long lastUpdate = -interval;
boolean forceUpdate = true;
float tempC;
byte dsAddr[8];

struct {
	boolean pressed;
	unsigned long debounce;
} buttonStates[buttonCount];

LiquidCrystal lcd(12, 11, 5, 4, 3, 2);
OneWire oneWire(dsTempPin);
DallasTemperature ds(&oneWire);

int formatInt(int val, char *buf, int len)
{
	int i = 0;
	int j = 0;
	
	/* Handle negative */
	if (val < 0) {
		val = -val;
		i++;
		j++;
	}
	
	/* Extract each digit */
	do {
		buf[j++] = '0' + val % 10;
		val /= 10;
	} while (val != 0 || j < len);
	buf[j] = 0;
	len = j;
	
	/* Reverse */
	for (j--; i < j; i++, j--) {
		char tmp = buf[i];
		buf[i] = buf[j];
		buf[j] = tmp;
	}
	
	return len;
}

int formatTemp(float temp, char *buf)
{
	int len = formatInt(int(temp), buf, 0);
	buf[len] = '.';
	buf[len + 1] = '0' + int(temp * 10) % 10;
	buf[len + 2] = 0;
	return len + 2;
}

int formatTime(unsigned long time, char *buf)
{
	time /= 1000;
	int ss = time % 60;
	time /= 60;
	int mm = time % 60;
	time /= 60;
	int hh = time;
	
	char *p = buf;
	if (hh > 0) {
		formatInt(hh, p, 2);
		p[2] = ':';
		p += 3;
	}
	
	formatInt(mm, p, 2);
	p[2] = ':';
	p += 3;
	
	formatInt(ss, p, 2);
	
	return int(p - buf) + 2;
}

void handleKeyPressed(int key)
{
	if (key == 0)
		firstMode = (firstMode + 1) % FIRST_MAX;
	else if (key == 1)
		secondMode = (secondMode + 1) % SECOND_MAX;
	forceUpdate = true;
}

void setup()
{
	lcd.begin(16, 2);
	for (int i = 0; i < buttonCount; i++)
		pinMode(buttonPins[i], INPUT);
	ds.setResolution(12);
	ds.begin();
	ds.getAddress(dsAddr, 0);
}

void loop()
{
	unsigned long current = millis();
	
	/* Split temperature reading and LCD update */
	if (current - lastUpdate >= interval) {
		forceUpdate = true;
		lastUpdate = current;
		ds.requestTemperaturesByAddress(dsAddr);
		tempC = ds.getTempC(dsAddr);
	}

	/* Is it time to update? */
	if (forceUpdate) {
		forceUpdate = false;
	
		float temp;
		char unit;
		if (firstMode == FAHRENHEIT) {
			temp = tempC * 9 / 5 + 32;
			unit = 'F';
		} else {
			temp = tempC;
			unit = 'C';
		}
		
		/* Print first line */
		char line[17];
		char buf[10];
		int len = formatTemp(temp, buf);
		memset(line, ' ', sizeof(line) - 1);
		memcpy(line, "Temp 1:", 7);
		memcpy(&line[13 - len], buf, len);
		line[14] = '\xDF';
		line[15] = unit;
		line[16] = 0;
		
		lcd.setCursor(0, 0);
		lcd.print(line);
		
		/* Print second line */
		memset(line, ' ', sizeof(line) - 1);
		if (secondMode == TEMP2) {
			int sum = 0;
			for (int i = 0; i < tempSamples; i++) {
				sum += analogRead(lmTempPin);
			}
			temp = sum * 500.0 / 1023 / tempSamples;
			unit = 'C';
			
			if (firstMode == FAHRENHEIT) {
				temp = temp * 9 / 5 + 32;
				unit = 'F';
			}
			
			memcpy(line, "Temp 2:", 7);
			len = formatTemp(temp, buf);
			buf[len++] = ' ';
			buf[len++] = '\xDF';
			buf[len++] = unit;
			buf[len] = 0;
		} else if (secondMode == LIGHT) {
			memcpy(line, "Light:", 6);
			len = formatInt(analogRead(lightPin), buf, 0);
		} else if (secondMode == TIMER) {
			memcpy(line, "Uptime:", 7);
			len = formatTime(current, buf);
		} else {
			memcpy(line, "Delta:", 6);
			len = formatInt(millis() - current, buf, 0);
		}
		memcpy(&line[16 - len], buf, len);
		line[16] = 0;
		
		lcd.setCursor(0, 1);
		lcd.print(line);
	}
	
	/* Handle button events */
	current = millis();
	for (int i = 0; i < buttonCount; i++) {
		boolean lastPressed = buttonStates[i].pressed;
		boolean pressed = digitalRead(buttonPins[i]) == HIGH;
		if (buttonStates[i].debounce == 0) {
			/* Start debouncing */
			if (pressed != lastPressed)
				buttonStates[i].debounce = current;
		} else if (current - buttonStates[i].debounce >= debounceDelay) {
			/* Stop debouncing */
			buttonStates[i].pressed = pressed;
			buttonStates[i].debounce = 0;
			if (!lastPressed && pressed)
				handleKeyPressed(i);
		}
	}
}
