if RUBY_VERSION < "1.9"
  require 'dl/import'
  require 'dl/struct'
elsif RUBY_VERSION < "2.2"
  require 'dl/import'
  require 'dl/types'
  require 'dl'
else
  require 'fiddle'
  require 'fiddle/types'
  require 'fiddle/import'

  # For now map DL to Fiddler versus updating all the code below
  module DL
    CPtr = Fiddle::Pointer
    RUBY_FREE = Fiddle::RUBY_FREE
  end
end

require 'net/ssh/errors'

module Net; module SSH; module Authentication

  # This module encapsulates the implementation of a socket factory that
  # uses the PuTTY "pageant" utility to obtain information about SSH
  # identities.
  #
  # This code is a slightly modified version of the original implementation
  # by Guillaume Marçais (guillaume.marcais@free.fr). It is used and
  # relicensed by permission.
  module Pageant

    # From Putty pageant.c
    AGENT_MAX_MSGLEN = 8192
    AGENT_COPYDATA_ID = 0x804e50ba

    # The definition of the Windows methods and data structures used in
    # communicating with the pageant process.
    module Win
      # Compatibility on initialization
      if RUBY_VERSION < "1.9"
        extend DL::Importable

        dlload 'user32'
        dlload 'kernel32'
        dlload 'advapi32'

        SIZEOF_DWORD = DL.sizeof('L')
      elsif RUBY_VERSION < "2.2"
        extend DL::Importer
        dlload 'user32','kernel32', 'advapi32'
        include DL::Win32Types

        SIZEOF_DWORD = DL::SIZEOF_LONG
      else
        extend Fiddle::Importer
        dlload 'user32','kernel32', 'advapi32'
        include Fiddle::Win32Types
        SIZEOF_DWORD = Fiddle::SIZEOF_LONG
      end

      typealias("LPCTSTR", "char *")         # From winnt.h
      typealias("LPVOID", "void *")          # From winnt.h
      typealias("LPCVOID", "const void *")   # From windef.h
      typealias("LRESULT", "long")           # From windef.h
      typealias("WPARAM", "unsigned int *")  # From windef.h
      typealias("LPARAM", "long *")          # From windef.h
      typealias("PDWORD_PTR", "long *")      # From basetsd.h
      typealias("USHORT", "unsigned short")  # From windef.h

      # From winbase.h, winnt.h
      INVALID_HANDLE_VALUE = -1
      NULL = nil
      PAGE_READWRITE = 0x0004
      FILE_MAP_WRITE = 2
      WM_COPYDATA = 74

      SMTO_NORMAL = 0   # From winuser.h

      # args: lpClassName, lpWindowName
      extern 'HWND FindWindow(LPCTSTR, LPCTSTR)'

      # args: none
      extern 'DWORD GetCurrentThreadId()'

      # args: hFile, (ignored), flProtect, dwMaximumSizeHigh,
      #           dwMaximumSizeLow, lpName
      extern 'HANDLE CreateFileMapping(HANDLE, void *, DWORD, ' +
        'DWORD, DWORD, LPCTSTR)'

      # args: hFileMappingObject, dwDesiredAccess, dwFileOffsetHigh, 
      #           dwfileOffsetLow, dwNumberOfBytesToMap
      extern 'LPVOID MapViewOfFile(HANDLE, DWORD, DWORD, DWORD, DWORD)'

      # args: lpBaseAddress
      extern 'BOOL UnmapViewOfFile(LPCVOID)'

      # args: hObject
      extern 'BOOL CloseHandle(HANDLE)'

      # args: hWnd, Msg, wParam, lParam, fuFlags, uTimeout, lpdwResult
      extern 'LRESULT SendMessageTimeout(HWND, UINT, WPARAM, LPARAM, ' +
        'UINT, UINT, PDWORD_PTR)'
      
      # args: none
      extern 'DWORD GetLastError()'

      # args: none
      extern 'HANDLE GetCurrentProcess()'

      # args: hProcessHandle, dwDesiredAccess, (out) phNewTokenHandle
      extern 'BOOL OpenProcessToken(HANDLE, DWORD, PHANDLE)'

      # args: hTokenHandle, uTokenInformationClass,
      #           (out) lpTokenInformation, dwTokenInformationLength
      #           (out) pdwInfoReturnLength
      extern 'BOOL GetTokenInformation(HANDLE, UINT, LPVOID, DWORD, ' +
        'PDWORD)'

      # args: (out) lpSecurityDescriptor, dwRevisionLevel
      extern 'BOOL InitializeSecurityDescriptor(LPVOID, DWORD)'

      # args: (out) lpSecurityDescriptor, lpOwnerSid, bOwnerDefaulted
      extern 'BOOL SetSecurityDescriptorOwner(LPVOID, LPVOID, BOOL)'

      # args: pSecurityDescriptor
      extern 'BOOL IsValidSecurityDescriptor(LPVOID)'

      # Constants needed for security attribute retrieval.
      # Specifies the access mask corresponding to the desired access 
      # rights. 
      TOKEN_QUERY = 0x8

      # The value of TOKEN_USER from the TOKEN_INFORMATION_CLASS enum.
      TOKEN_USER_INFORMATION_CLASS = 1

      # The initial revision level assigned to the security descriptor.
      REVISION = 1

      # Structs for security attribute functions.
      # Holds the retrieved user access token.
      TOKEN_USER = struct ['void * SID', 'DWORD ATTRIBUTES']

      # Contains the security descriptor, this gets passed to the
      # function that constructs the shared memory map.
      SECURITY_ATTRIBUTES = struct ['DWORD nLength',
                                    'LPVOID lpSecurityDescriptor',
                                    'BOOL bInheritHandle']

      # The security descriptor holds security information.
      SECURITY_DESCRIPTOR = struct ['UCHAR Revision', 'UCHAR Sbz1',
                                    'USHORT Control', 'LPVOID Owner',
                                    'LPVOID Group', 'LPVOID Sacl',
                                    'LPVOID Dacl']

      # Compatibility for security attribute retrieval.
      if RUBY_VERSION < "1.9"
        # Alias functions to > 1.9 capitalization
        %w(findWindow
           getCurrentProcess
           initializeSecurityDescriptor
           setSecurityDescriptorOwner
           isValidSecurityDescriptor
           openProcessToken
           getTokenInformation
           getLastError
           getCurrentThreadId
           createFileMapping
           mapViewOfFile
           sendMessageTimeout
           unmapViewOfFile
           closeHandle).each do |name|
          new_name = name[0].chr.upcase + name[1..name.length]
          alias_method new_name, name
          module_function new_name
        end

        def self.malloc_ptr(size)
          return DL.malloc(size)
        end

        def self.get_ptr(data)
          return data.to_ptr
        end

        def self.set_ptr_data(ptr, data)
          ptr[0] = data
        end
      else
        def self.malloc_ptr(size)
          return DL::CPtr.malloc(size, DL::RUBY_FREE)
        end

        def self.get_ptr(data)
          return DL::CPtr.to_ptr data
        end

        def self.set_ptr_data(ptr, data)
          DL::CPtr.new(ptr)[0,data.size] = data
        end
      end

      def self.get_security_attributes_for_user
        user = get_current_user

        psd_information = malloc_ptr(Win::SECURITY_DESCRIPTOR.size)
        raise_error_if_zero(
          Win.InitializeSecurityDescriptor(psd_information,
                                           Win::REVISION))
        raise_error_if_zero(
          Win.SetSecurityDescriptorOwner(psd_information, user.SID,
                                         0))
        raise_error_if_zero(
          Win.IsValidSecurityDescriptor(psd_information))

        sa = Win::SECURITY_ATTRIBUTES.new(malloc_ptr(Win::SECURITY_ATTRIBUTES.size))
        sa.nLength = Win::SECURITY_ATTRIBUTES.size
        sa.lpSecurityDescriptor = psd_information.to_i
        sa.bInheritHandle = 1

        return sa
      end

      def self.get_current_user
        token_handle = open_process_token(Win.GetCurrentProcess,
                                          Win::TOKEN_QUERY)
        token_user =  get_token_information(token_handle,
                        Win::TOKEN_USER_INFORMATION_CLASS)
        return token_user
      end

      def self.open_process_token(process_handle, desired_access)
        ptoken_handle = malloc_ptr(Win::SIZEOF_DWORD)

        raise_error_if_zero(
          Win.OpenProcessToken(process_handle, desired_access,
                               ptoken_handle))
        token_handle = ptoken_handle.ptr.to_i

        return token_handle
      end

      def self.get_token_information(token_handle,
                                     token_information_class)
        # Hold the size of the information to be returned
        preturn_length = malloc_ptr(Win::SIZEOF_DWORD)

        # Going to throw an INSUFFICIENT_BUFFER_ERROR, but that is ok
        # here. This is retrieving the size of the information to be
        # returned.
        Win.GetTokenInformation(token_handle,
                                token_information_class,
                                Win::NULL, 0, preturn_length)
        ptoken_information = malloc_ptr(preturn_length.ptr.to_i)

        # This call is going to write the requested information to
        # the memory location referenced by token_information.
        raise_error_if_zero(
          Win.GetTokenInformation(token_handle,
                                  token_information_class,
                                  ptoken_information,
                                  ptoken_information.size,
                                  preturn_length))

        return TOKEN_USER.new(ptoken_information)
      end

      def self.raise_error_if_zero(result)
        if result == 0
          raise "Windows error: #{Win.GetLastError}"
        end
      end

      # Get a null-terminated string given a string.
      def self.get_cstr(str)
        return str + "\000"
      end
    end

    # This is the pseudo-socket implementation that mimics the interface of
    # a socket, translating each request into a Windows messaging call to
    # the pageant daemon. This allows pageant support to be implemented
    # simply by replacing the socket factory used by the Agent class.
    class Socket

      private_class_method :new

      # The factory method for creating a new Socket instance. The location
      # parameter is ignored, and is only needed for compatibility with
      # the general Socket interface.
      def self.open(location=nil)
        new
      end

      # Create a new instance that communicates with the running pageant 
      # instance. If no such instance is running, this will cause an error.
      def initialize
        @win = Win.FindWindow("Pageant", "Pageant")

        if @win == 0
          raise Net::SSH::Exception,
            "pageant process not running"
        end

        @input_buffer = Net::SSH::Buffer.new
        @output_buffer = Net::SSH::Buffer.new
      end

      # Forwards the data to #send_query, ignoring any arguments after
      # the first.
      def send(data, *args)
        @input_buffer.append(data)
        
        ret = data.length
        
        while true
          return ret if @input_buffer.length < 4
          msg_length = @input_buffer.read_long + 4
          @input_buffer.reset!
      
          return ret if @input_buffer.length < msg_length
          msg = @input_buffer.read!(msg_length)
          @output_buffer.append(send_query(msg))
        end
      end
      
      # Reads +n+ bytes from the cached result of the last query. If +n+
      # is +nil+, returns all remaining data from the last query.
      def read(n = nil)
        @output_buffer.read(n)
      end

      def close
      end

      # Packages the given query string and sends it to the pageant
      # process via the Windows messaging subsystem. The result is
      # cached, to be returned piece-wise when #read is called.
      def send_query(query)
        res = nil
        filemap = 0
        ptr = nil
        id = Win.malloc_ptr(Win::SIZEOF_DWORD)

        mapname = "PageantRequest%08x" % Win.GetCurrentThreadId()
        security_attributes = Win.get_ptr Win.get_security_attributes_for_user

        filemap = Win.CreateFileMapping(Win::INVALID_HANDLE_VALUE,
                                        security_attributes,
                                        Win::PAGE_READWRITE, 0,
                                        AGENT_MAX_MSGLEN, mapname)

        if filemap == 0 || filemap == Win::INVALID_HANDLE_VALUE
          raise Net::SSH::Exception,
            "Creation of file mapping failed with error: #{Win.GetLastError}"
        end

        ptr = Win.MapViewOfFile(filemap, Win::FILE_MAP_WRITE, 0, 0, 
                                0)

        if ptr.nil? || ptr.null?
          raise Net::SSH::Exception, "Mapping of file failed"
        end

        Win.set_ptr_data(ptr, query)

        cds = Win.get_ptr [AGENT_COPYDATA_ID, mapname.size + 1,
                           Win.get_cstr(mapname)].pack("LLp")
        succ = Win.SendMessageTimeout(@win, Win::WM_COPYDATA, Win::NULL,
                                      cds, Win::SMTO_NORMAL, 5000, id)

        if succ > 0
          retlen = 4 + ptr.to_s(4).unpack("N")[0]
          res = ptr.to_s(retlen)
        else
          raise Net::SSH::Exception, "Message failed with error: #{Win.GetLastError}"
        end

        return res
      ensure
        Win.UnmapViewOfFile(ptr) unless ptr.nil? || ptr.null?
        Win.CloseHandle(filemap) if filemap != 0
      end
    end
  end

end; end; end
