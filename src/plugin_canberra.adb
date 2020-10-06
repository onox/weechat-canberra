--  SPDX-License-Identifier: Apache-2.0
--
--  Copyright (c) 2020 onox <denkpadje@gmail.com>
--
--  Licensed under the Apache License, Version 2.0 (the "License");
--  you may not use this file except in compliance with the License.
--  You may obtain a copy of the License at
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
--  Unless required by applicable law or agreed to in writing, software
--  distributed under the License is distributed on an "AS IS" BASIS,
--  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--  See the License for the specific language governing permissions and
--  limitations under the License.

with System;

with Interfaces.C.Strings;

with Ada.Calendar.Formatting;
with Ada.Calendar.Time_Zones;
with Ada.Unchecked_Conversion;

with Canberra;

with WeeChat;

package body Plugin_Canberra is

   --  Play sounds when a message is received, nick name is highlighted, or
   --  when client got (dis)connected to IRC server.

   Sound_Message                : constant String := "message";
   --  Not away and new message:

   Sound_Message_Highlight      : constant String := "message-new-instant";
   --  Not away and (PM or nick highlighted):

   Sound_Message_Highlight_Away : constant String := "phone-incoming-call";
   --  Away and (PM or nick highlighted) and current time is during office hours

   Sound_Message_Reminder       : constant String := "phone-outgoing-busy";
   --  Away and (PM or nick highlighted) and current time outside office hours
   --  (Played in the morning for x minutes or until not away)

   Sound_Server_Connected    : constant String := "service-login";
   --  Plugin initalized or connected to IRC server:

   Sound_Server_Disconnected : constant String := "service-logout";
   --  Disconnected from IRC server:

   Away_Duration    : constant Duration := 30.0 * 60.0;
   Retry_Duration   : constant Duration := 30.0;
   Reminder_Retries : constant Positive := 10;

   Office_Hour_Start : constant Duration := Ada.Calendar.Formatting.Seconds_Of (7, 0);
   Office_Hour_End   : constant Duration := Ada.Calendar.Formatting.Seconds_Of (21, 0);

   -----------------------------------------------------------------------------

   Last_Key_Press : Ada.Calendar.Time := Ada.Calendar.Clock;

   Is_Highlighted_While_Away : Boolean := False;

   use Ada.Calendar;

   function Image_Date (Date : Ada.Calendar.Time) return String is
     (Formatting.Image (Date, Time_Zone => Time_Zones.UTC_Time_Offset));

   function Image_Time (Time : Duration) return String is
     (Formatting.Image (Time));

   -----------------------------------------------------------------------------

   Context : Canberra.Context := Canberra.Create;

   procedure Play_Async (Event : String) is
      S1 : Canberra.Sound;
   begin
      Context.Play (Event, S1);
   end Play_Async;

   -----------------------------------------------------------------------------

   use WeeChat;

   Reminder_Timer : Timer;

   function Reminder_Repeated_Call_Handler
     (Plugin          : Plugin_Ptr;
      Remaining_Calls : Integer) return Callback_Result is
   begin
      if Is_Highlighted_While_Away then
         Play_Async (Sound_Message_Reminder);
         if Remaining_Calls = 0 then
            Reminder_Timer := No_Timer;
         end if;
      else
         Cancel_Timer (Reminder_Timer);
         Reminder_Timer := No_Timer;
      end if;
      return OK;
   end Reminder_Repeated_Call_Handler;

   function Reminder_First_Call_Handler
     (Plugin          : Plugin_Ptr;
      Remaining_Calls : Integer) return Callback_Result is
   begin
      if Is_Highlighted_While_Away then
         Play_Async (Sound_Message_Reminder);

         Reminder_Timer := Set_Timer (Plugin, Retry_Duration, 0, Reminder_Retries,
           Reminder_Repeated_Call_Handler'Access);
      else
         Reminder_Timer := No_Timer;
      end if;
      return OK;
   end Reminder_First_Call_Handler;

   -----------------------------------------------------------------------------

   function On_Key_Press_Signal
     (Plugin      : Plugin_Ptr;
      Signal      : String;
      Kind        : Data_Kind;
      Signal_Data : Void_Ptr) return Callback_Result is
   begin
      Is_Highlighted_While_Away := False;
      Last_Key_Press := Ada.Calendar.Clock;

      return OK;
   end On_Key_Press_Signal;

   function On_IRC_Signal
     (Plugin      : Plugin_Ptr;
      Signal      : String;
      Kind        : Data_Kind;
      Signal_Data : Void_Ptr) return Callback_Result is
   begin
      if Signal = "irc_server_connected" then
         Play_Async (Sound_Server_Connected);
      elsif Signal = "irc_server_disconnected" then
         Play_Async (Sound_Server_Disconnected);
      end if;

      return OK;
   end On_IRC_Signal;

   function On_IRC_Message_Signal
     (Plugin      : Plugin_Ptr;
      Signal      : String;
      Kind        : Data_Kind;
      Signal_Data : Void_Ptr) return Callback_Result
   is
      Signal_Splitted : constant String_List :=
        Split (Signal, Separator => ",", Maximum => 2);

      use type SU.Unbounded_String;

      Server_Name : SU.Unbounded_String renames Signal_Splitted (1);
      Signal_Name : SU.Unbounded_String renames Signal_Splitted (2);

      Nick_Name : constant String := Get_Info (Plugin, "irc_nick", +Server_Name);
   begin
      if Signal_Name /= "irc_in2_PRIVMSG" or Kind /= String_Type or Signal_Data = Null_Void then
         return Error;
      end if;

      declare
         use Interfaces.C.Strings;

         function Convert is new Ada.Unchecked_Conversion (Void_Ptr, chars_ptr);

         Message : constant String_List := Split (Value (Convert (Signal_Data)), Maximum => 4);

         From_User : SU.Unbounded_String renames Message (1);
         Primitive : SU.Unbounded_String renames Message (2);
         Channel   : SU.Unbounded_String renames Message (3);
         Text      : SU.Unbounded_String renames Message (4);
         pragma Assert (Primitive = "PRIVMSG");

         Is_Private_Message : constant Boolean := Channel = Nick_Name;
         Is_Highlighted     : constant Boolean := SU.Index (Text, ":" & Nick_Name & ": ") > 0;

         Is_Away : constant Boolean := Clock - Last_Key_Press > Away_Duration;
      begin
         if Is_Private_Message or Is_Highlighted then
            if not Is_Away then
               Play_Async (Sound_Message);
               Play_Async (Sound_Message_Highlight);
            else
               Is_Highlighted_While_Away := True;

               if Seconds (Clock) in Office_Hour_Start .. Office_Hour_End then
                  Cancel_Timer (Reminder_Timer);
                  Reminder_Timer := No_Timer;
                  Play_Async (Sound_Message_Highlight_Away);
               else
                  declare
                     Current_Time : constant Time := Clock;
                     Wake_Up_Date : constant Time := Current_Time - Seconds (Current_Time)
                         + (if Seconds (Clock) >= Office_Hour_End then Day_Duration'Last else 0.0)
                         + Office_Hour_Start;

                     In_Time : constant Duration := Wake_Up_Date - Current_Time;
                     Sender  : constant String   := Get_Nick (Host => +From_User);
                  begin
                     if Reminder_Timer = No_Timer then
                        Reminder_Timer := Set_Timer
                          (Plugin, In_Time, 60, 1, Reminder_First_Call_Handler'Access);

                        Send_Message
                          (Plugin, +Server_Name,
                           (if Is_Private_Message then Sender else +Channel),
                           (if Is_Private_Message then "" else Sender & ": ") &
                           "I'm currently away since " & Image_Date (Last_Key_Press) &
                           ". I will try to notify myself in about " &
                           Image_Time (In_Time) & " hours");
                     end if;
                  end;
               end if;
            end if;
         elsif not Is_Away then
            Play_Async (Sound_Message);
         end if;
      end;

      return OK;
   end On_IRC_Message_Signal;

   procedure Plugin_Initialize (Plugin : Plugin_Ptr) is
   begin
      On_Signal (Plugin, "key_pressed", On_Key_Press_Signal'Access);
      On_Signal (Plugin, "irc_*", On_IRC_Signal'Access);
      On_Signal (Plugin, "*,irc_in2_PRIVMSG", On_IRC_Message_Signal'Access);

      Play_Async (Sound_Server_Connected);
   end Plugin_Initialize;

   procedure Plugin_Finalize (Plugin : Plugin_Ptr) is null;

   Plugin_Name : constant C_String := "canberra" & L1.NUL
     with Export, Convention => C, External_Name => "weechat_plugin_name";

   Plugin_Author : constant C_String := "onox" & L1.NUL
     with Export, Convention => C, External_Name => "weechat_plugin_author";

   Plugin_Description : constant C_String := "Canberra sounds with Ada 2012" & L1.NUL
     with Export, Convention => C, External_Name => "weechat_plugin_description";

   Plugin_Version : constant C_String := "1.0" & L1.NUL
     with Export, Convention  => C, External_Name => "weechat_plugin_version";

   Plugin_License : constant C_String := "Apache-2.0" & L1.NUL
     with Export, Convention => C, External_Name => "weechat_plugin_license";

   Plugin_API_Version : constant String := WeeChat.Plugin_API_Version
     with Export, Convention => C, External_Name => "weechat_plugin_api_version";

   function Plugin_Init
     (Object : Plugin_Ptr;
      Argc   : Interfaces.C.int;
      Argv   : System.Address) return Callback_Result
   with Export, Convention => C, External_Name => "weechat_plugin_init";

   function Plugin_End (Object : Plugin_Ptr) return Callback_Result
     with Export, Convention => C, External_Name => "weechat_plugin_end";

   function Plugin_Init
     (Object : Plugin_Ptr;
      Argc   : Interfaces.C.int;
      Argv   : System.Address) return Callback_Result is
   begin
      return Plugin_Init (Object, Plugin_Initialize'Access);
   end Plugin_Init;

   function Plugin_End (Object : Plugin_Ptr) return Callback_Result is
   begin
      return Plugin_End (Object, Plugin_Finalize'Access);
   end Plugin_End;

end Plugin_Canberra;
