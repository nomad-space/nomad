pragma solidity ^0.4.11;

import "./zeppelin-solidity/ownership/Ownable.sol";
import "./zeppelin-solidity/ownership/Claimable.sol";
import "./zeppelin-solidity/token/StandardToken.sol";

contract Abab is Ownable,Claimable,StandardToken {
  uint constant maxUInt = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
  uint constant error   = maxUInt;

  event log(string s);
  event logUint(string s, uint i);

  struct  Schedule {
    uint from;
    uint to;          // last day, when can I stay overnight
    uint dayPrice;
    uint weekPrice;
    uint monthPrice;
    uint currency;    // see Currencies array
  }

  enum BookingStatus { New, Agreed, Cancel, Complete } // TODO Complete? 

  struct  BookingRecord {
    address guest;
    uint from;
    uint to;
    uint totalCost;
    uint currency;
    uint ababCoinTotalCost;
    BookingStatus status;
  }

  struct Room {
    uint160 roomDescriptionHash;
    address partner;
    uint    partnerPPM;
    uint    minNightCount;
    uint    timeForBooking;    
    uint    schedulesLength;
    uint    bookingLength;
    mapping(uint => Schedule) schedules;
    mapping(uint => BookingRecord) booking;
  }

  mapping (address => Room[]) public rooms;

  string[] Currencies = ["AbabCoin", "ETH", "BTC", "USD", "RUR"];

  function GetCurrencyByIndex(uint i)
  public constant
  returns(string currencyName)
  {
    return Currencies[i]; 
  }

  function GetCurrencyIndexByName(string name)
  public constant
  returns(uint index)
  {
    for(uint i = 0;i<Currencies.length;++i)
      if (sha3(Currencies[i]) == sha3(name))  // https://ethereum.stackexchange.com/questions/4559/operator-not-compatible-with-type-string-storage-ref-and-literal-string
        return i;
    return error;
  }

  event NewCurrency(string name, uint index);

  function AddCurrency(string name)
  public onlyOwner
  returns(uint index)
  {
    index = GetCurrencyIndexByName(name);
    if (index == error) {
      index = Currencies.push(name) - 1;
      NewCurrency(name, index);
    }
    return index;
  }

  event NewRoom    (address indexed host, uint roomIndex, uint160 _roomDescriptionHash);
  event UpdateRoom (address indexed host, uint roomIndex, uint160 _newRoomDescriptionHash);
  event DeleteRoom (address indexed host, uint roomIndex);  

  function UpsertRoomFromHost(
    uint    _roomIndex, 
    uint160 _roomDescriptionHash, 
    address _partner, 
    uint    _partnerPPM, 
    uint    _minNightCount,
    uint    _timeForBooking)
  public
  returns (uint roomIndex)
  {
    return UpsertRoom(_roomIndex, _roomDescriptionHash, msg.sender, _partner, _partnerPPM, _minNightCount, _timeForBooking);
  }

  function UpsertRoomFromPartner(
    uint    _roomIndex, 
    uint160 _roomDescriptionHash, 
    address _host, 
    uint    _partnerPPM,
    uint    _minNightCount,
    uint    _timeForBooking)
  public
  returns (uint roomIndex)
  {
    return UpsertRoom(_roomIndex, _roomDescriptionHash, _host, msg.sender, _partnerPPM, _minNightCount, _timeForBooking);
  }

  function UpsertRoom(
    uint    _roomIndex, 
    uint160 _roomDescriptionHash,
    address _host,
    address _partner,
    uint    _partnerPPM,
    uint    _minNightCount,
    uint    _timeForBooking)
  public
  returns (uint roomIndex)
  {
    if(_roomIndex>=rooms[_host].length) {
      var newRoomIndex = rooms[_host].push(  Room(_roomDescriptionHash, _partner, _partnerPPM, _minNightCount, _timeForBooking, 0, 0) )-1;
      NewRoom(msg.sender, newRoomIndex, _roomDescriptionHash);
      return newRoomIndex;
    }

    if((rooms[_host][_roomIndex].partner != msg.sender) && (_host != msg.sender) )
      return;

    rooms[_host][_roomIndex].roomDescriptionHash = _roomDescriptionHash;
    rooms[_host][_roomIndex].partner             = _partner;
    rooms[_host][_roomIndex].partnerPPM          = _partnerPPM;
    rooms[_host][_roomIndex].minNightCount       = _minNightCount;
    rooms[_host][_roomIndex].timeForBooking      = _timeForBooking;

    UpdateRoom(_host, _roomIndex, _roomDescriptionHash);
    return _roomIndex;
  }

  function GetRoomsCount()
  public constant
  returns (uint count)
  {
    return rooms[msg.sender].length;
  }

  function GetDescriptionHash(uint _roomIndex)
    public constant
  returns (uint160 DescriptionHash) 
  {
    return rooms[msg.sender][_roomIndex].roomDescriptionHash;
  }

  function RemoveRoomFromPartner(address _host, uint _roomIndex)
  public
  {
    if (_roomIndex >= rooms[_host].length)
      return;
    if((rooms[_host][_roomIndex].partner != msg.sender) && (_host != msg.sender) )
      return;
      
    for (uint i = _roomIndex; i<rooms[_host].length-1; ++i)
      rooms[_host][i] = rooms[_host][i+1];

    --rooms[_host].length;

    DeleteRoom(_host, _roomIndex);
  }

  function RemoveRoom(uint _roomIndex)
  public
  {
    RemoveRoomFromPartner(msg.sender, _roomIndex);
  }

  event NewSchedule    (address indexed host, uint roomIndex, uint scheduleIndex);
  event UpdateSchedule (address indexed host, uint roomIndex, uint scheduleIndex);
  event DeleteSchedule (address indexed host, uint roomIndex, uint scheduleIndex);  

  function UpsertScheduleFromPartner(
    address _host, 
    uint _roomIndex, 
    uint _scheduleIndex, 
    uint _from, 
    uint _to,               // last day, when can I stay overnight
    uint _dayPrice, 
    uint _weekPrice, 
    uint _monthPrice, 
    uint _currency)
  public
  {
    if (_roomIndex >= rooms[_host].length)
      return;
    if((rooms[_host][_roomIndex].partner != msg.sender) && (_host != msg.sender) )
      return;

    var schedule = Schedule(_from, _to, _dayPrice, _weekPrice, _monthPrice, _currency);

    var room = rooms[_host][_roomIndex];
    var schedulesLength = room.schedulesLength;

    if(_scheduleIndex<schedulesLength) {
      // update
      room.schedules[_scheduleIndex] = schedule;
      UpdateSchedule (_host, _roomIndex, _scheduleIndex);
    } else {
      //insert
      room.schedules[schedulesLength] = schedule;
      NewSchedule(_host, _roomIndex, schedulesLength);
      room.schedulesLength = schedulesLength + 1;
    }
  }

  function UpsertSchedule(
    uint _roomIndex, 
    uint _scheduleIndex, 
    uint _from, 
    uint _to,               // last day, when can I stay overnight
    uint _dayPrice, 
    uint _weekPrice, 
    uint _monthPrice, 
    uint _currency)
  public
  {
    UpsertScheduleFromPartner(msg.sender, _roomIndex, _scheduleIndex, _from, _to, _dayPrice, _weekPrice, _monthPrice, _currency);
  }

  function GetScheduleIndex(uint _roomIndex, uint _from)
    public constant 
    returns (uint index) 
  {
    for(uint i=0; i<rooms[msg.sender][_roomIndex].schedulesLength; ++i)
      if(rooms[msg.sender][_roomIndex].schedules[i].from == _from) 
        return i;
    return maxUInt;
  }

  function GetSchedulesLength(uint _roomIndex) 
  public constant 
  returns(uint length) 
  {
      var addressRooms = rooms[msg.sender];
      if (addressRooms.length <= _roomIndex) 
          return 0;
      return rooms[msg.sender][_roomIndex].schedulesLength;
    }

  function GetScheduleByIndex(address _host, uint _roomIndex, uint _index)
  public constant 
  returns(uint from, uint to, uint dayPrice, uint weekPrice, uint monthPrice) 
  {
      var s = rooms[_host][_roomIndex].schedules[_index];
      return (s.from, s.to, s.dayPrice, s.weekPrice, s.monthPrice);
  }

  function GetMyScheduleByIndex(uint _roomIndex, uint _index) 
  public constant 
  returns(uint from, uint to, uint dayPrice, uint weekPrice, uint monthPrice) 
  {
      return GetScheduleByIndex(msg.sender, _roomIndex, _index);
  }

  function RemoveSchedule(uint _roomIndex, uint _scheduleIndex)
  public
  {
    if(_scheduleIndex>=rooms[msg.sender][_roomIndex].schedulesLength)
      return;

    var length = rooms[msg.sender][_roomIndex].schedulesLength - 1;

    for (uint i = _scheduleIndex; i<length; ++i)
      rooms[msg.sender][_roomIndex].schedules[i] = rooms[msg.sender][_roomIndex].schedules[i+1];

    rooms[msg.sender][_roomIndex].schedulesLength = length;
    DeleteSchedule(msg.sender,_roomIndex, _scheduleIndex);
  }

  event NewBooking    (address indexed host, uint roomIndex, uint bookingIndex);
  event UpdateBooking (address indexed host, uint roomIndex, uint bookingIndex);

  function GetDate(uint timestamp)
  public constant
  returns(uint result)
  {
    return timestamp/1 days;
  }

  function GetTime(uint datetime)
  public constant
  returns(uint result)
  {
    uint dayCount = datetime / 1 days;
    return datetime - 1 days * dayCount;
  }

  function DateIsFree(address _host, uint _roomIndex, uint _from, uint _to, uint nowDateTime)
  public constant
  returns(bool result)
  {
    var room = rooms[_host][_roomIndex];
    var nowDate = GetDate(nowDateTime);

    if ((_from + room.minNightCount) > _to) return false;
    if (_from < nowDate) return false;
    if ((_from == nowDate) && (nowDate >= room.timeForBooking)) return false;

    //check, that this date don't booking
    uint i = room.bookingLength;
    while(i>0) {
      --i;
      var booking_i = room.booking[i];
      if (booking_i.status > BookingStatus.Agreed)  continue;
      if (booking_i.to < nowDate) continue; 
      if (!((booking_i.from > _to)||(booking_i.to <= _from))) return false;
    }
    return true; 
  }

  function min(uint arg1, uint arg2, uint arg3)
  public 
  constant
  returns(uint result)
  {
    if((arg1<arg2)&&(arg1<arg3)) return arg1;
    if((arg2<arg1)&&(arg2<arg3)) return arg2;
    return arg3;
  }

  function CalcTotalCost(address _host, uint _roomIndex, uint _from, uint _to, uint _nowDateTime)
  public constant
  returns(uint totalCost)
  {
    totalCost = 0;

    //check, that this date don't booking
    if(!DateIsFree(_host, _roomIndex, _from, _to, _nowDateTime)) return 0;

    var room = rooms[_host][_roomIndex];

    var schedulesLength = rooms[_host][_roomIndex].schedulesLength;

    uint needFrom  = _from;
    uint nextFrom  = maxUInt;
    uint daysCount = _to-_from;

    // log2('needFrom=' ,needFrom);
    // log2('nextFrom=' ,nextFrom);
    // log2('daysCount=',daysCount);
    // log2('totalCost=',totalCost);

    uint i = schedulesLength;
    while(i>0){
      --i;
      var schedules_i = room.schedules[i];
      if ((schedules_i.from<=needFrom) && (schedules_i.to>needFrom)) {
        // log('==================');
        // log2('iiiiiiii= ', i);
        // log2('needFrom= ', needFrom);
        // log2('nextFrom= ', nextFrom);

        uint price = daysCount>=30 ? schedules_i.monthPrice : daysCount>=7 ? schedules_i.weekPrice : schedules_i.dayPrice;
        totalCost += price*(min( schedules_i.to, nextFrom, _to) - needFrom);
        needFrom = schedules_i.to<nextFrom ? schedules_i.to : nextFrom;

        // log('-----------------');
        // log2('price='   ,price);
        // log2('needFrom=' ,needFrom);
        // log2('totalCost=',totalCost);
        
        if(needFrom>=_to) return totalCost;
 
        //needFrom = nextFrom;
        nextFrom = _to;
        // log2('nextFrom set _to=' ,nextFrom);
        i = schedulesLength;
      } else {
        if ((schedules_i.from>needFrom)&&(schedules_i.from<nextFrom)){
          nextFrom = schedules_i.from;
          // log2('nextFrom set schedules_i.from =' ,nextFrom);
        }
      }
    }
    return 0;
  }

  function Booking(address _host, uint _roomIndex, uint _from, uint _to)
  public
  {
    if (_from < GetDate(now)) return;
    var room = rooms[_host][_roomIndex];

    uint totalCost = CalcTotalCost(_host, _roomIndex, _from, _to, now);
    if(totalCost>0) {
      NewBooking(_host, _roomIndex, room.bookingLength);
      room.booking[ room.bookingLength ] = BookingRecord(msg.sender, _from, _to, totalCost, 0, totalCost, BookingStatus.New);
      room.bookingLength = room.bookingLength + 1;
    }
  }

  function GetBookingLength(address _host, uint _roomIndex)
  public constant
  returns(uint result)
  {
    return rooms[_host][_roomIndex].bookingLength;
  }

  function GetBooking(address _host, uint _roomIndex, uint _bookingIndex)
  public constant
  returns(address guest, uint from, uint to, uint totalCost, uint currency, uint ababCoinTotalCost, BookingStatus status)
  {
    var b = rooms[_host][_roomIndex].booking[_bookingIndex];
    return (b.guest, b.from, b.to, b.totalCost, b.currency, b.ababCoinTotalCost, b.status);
  }

  function AgreeBooking(address _host, uint _roomIndex, uint _bookingIndex)
  public
  {
    if (_roomIndex >= rooms[_host].length)
      return;
    var room = rooms[_host][_roomIndex];
    if((room.partner != msg.sender) && (_host != msg.sender) )
      return;
    
    if (room.booking[_bookingIndex].status == BookingStatus.New){
      room.booking[_bookingIndex].status = BookingStatus.Agreed;
      UpdateBooking(_host, _roomIndex, _bookingIndex);
    }
  }

  function CancelBooking(address _host, uint _roomIndex, uint _bookingIndex)
  public
  {
    if (_roomIndex >= rooms[_host].length)
      return;
    var room = rooms[_host][_roomIndex];
    if((room.partner != msg.sender) && (_host != msg.sender) && (room.booking[_bookingIndex].guest != msg.sender) )
      return;
    
    if ((room.booking[_bookingIndex].status == BookingStatus.New) || (room.booking[_bookingIndex].status == BookingStatus.Agreed)){
      room.booking[_bookingIndex].status = BookingStatus.Cancel;
      UpdateBooking(_host, _roomIndex, _bookingIndex);
    }
  }
}