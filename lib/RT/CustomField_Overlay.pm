# BEGIN BPS TAGGED BLOCK {{{
# 
# COPYRIGHT:
#  
# This software is Copyright (c) 1996-2005 Best Practical Solutions, LLC 
#                                          <jesse@bestpractical.com>
# 
# (Except where explicitly superseded by other copyright notices)
# 
# 
# LICENSE:
# 
# This work is made available to you under the terms of Version 2 of
# the GNU General Public License. A copy of that license should have
# been provided with this software, but in any event can be snarfed
# from www.gnu.org.
# 
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
# 
# 
# CONTRIBUTION SUBMISSION POLICY:
# 
# (The following paragraph is not intended to limit the rights granted
# to you to modify and distribute this software under the terms of
# the GNU General Public License and is only of importance to you if
# you choose to contribute your changes and enhancements to the
# community by submitting them to Best Practical Solutions, LLC.)
# 
# By intentionally submitting any modifications, corrections or
# derivatives to this work, or any other work intended for use with
# Request Tracker, to Best Practical Solutions, LLC, you confirm that
# you are the copyright holder for those contributions and you grant
# Best Practical Solutions,  LLC a nonexclusive, worldwide, irrevocable,
# royalty-free, perpetual, license to use, copy, create derivative
# works based on those contributions, and sublicense and distribute
# those contributions and any derivatives thereof.
# 
# END BPS TAGGED BLOCK }}}
package RT::CustomField;

use strict;
no warnings qw(redefine);

use RT::CustomFieldValues;
use RT::ObjectCustomFieldValues;


our %FieldTypes = (
    Select => [
        'Select multiple values',    # loc
        'Select one value',        # loc
        'Select up to [_1] values',    # loc
    ],
    Freeform => [
        'Enter multiple values',    # loc
        'Enter one value',        # loc
        'Enter up to [_1] values',    # loc
    ],
    Text => [
        'Fill in multiple text areas',    # loc
        'Fill in one text area',    # loc
        'Fill in up to [_1] text areas',# loc
    ],
    Wikitext => [
        'Fill in multiple wikitext areas',    # loc
        'Fill in one wikitext area',    # loc
        'Fill in up to [_1] wikitext areas',# loc
    ],
    Image => [
        'Upload multiple images',    # loc
        'Upload one image',        # loc
        'Upload up to [_1] images',    # loc
    ],
    Binary => [
        'Upload multiple files',    # loc
        'Upload one file',        # loc
        'Upload up to [_1] files',    # loc
    ],
    Combobox => [
        'Combobox: Select or enter multiple values',    # loc
        'Combobox: Select or enter one value',        # loc
        'Combobox: Select or enter up to [_1] values',    # loc
    ],
    Autocomplete => [
        'Enter multiple values with autocompletion',    # loc
        'Enter one value with autocompletion',            # loc
        'Enter up to [_1] values with autocompletion',    # loc
    ],
);


our %FRIENDLY_OBJECT_TYPES =  ();

RT::CustomField->_ForObjectType( 'RT::Queue-RT::Ticket' => "Tickets", );    #loc
RT::CustomField->_ForObjectType(
    'RT::Queue-RT::Ticket-RT::Transaction' => "Ticket Transactions", );    #loc
RT::CustomField->_ForObjectType( 'RT::User'  => "Users", );                           #loc
RT::CustomField->_ForObjectType( 'RT::Group' => "Groups", );                          #loc

our $RIGHTS = {
    SeeCustomField            => 'See custom fields',       # loc_pair
    AdminCustomField          => 'Create, delete and modify custom fields',        # loc_pair
    ModifyCustomField         => 'Add, delete and modify custom field values for objects' #loc_pair
};

# Tell RT::ACE that this sort of object can get acls granted
$RT::ACE::OBJECT_TYPES{'RT::CustomField'} = 1;

foreach my $right ( keys %{$RIGHTS} ) {
    $RT::ACE::LOWERCASERIGHTNAMES{ lc $right } = $right;
}

sub AvailableRights {
    my $self = shift;
    return $RIGHTS;
}

=head1 NAME

  RT::CustomField_Overlay - overlay for RT::CustomField

=head1 DESCRIPTION

=head1 'CORE' METHODS

=head2 Create PARAMHASH

Create takes a hash of values and creates a row in the database:

  varchar(200) 'Name'.
  varchar(200) 'Type'.
  int(11) 'MaxValues'.
  varchar(255) 'Pattern'.
  smallint(6) 'Repeated'.
  varchar(255) 'Description'.
  int(11) 'SortOrder'.
  varchar(255) 'LookupType'.
  smallint(6) 'Disabled'.

C<LookupType> is generally the result of either
C<RT::Ticket->CustomFieldLookupType> or C<RT::Transaction->CustomFieldLookupType>.

=cut

sub Create {
    my $self = shift;
    my %args = (
        Name        => '',
        Type        => '',
        MaxValues   => 0,
        Pattern     => '',
        Description => '',
        Disabled    => 0,
        LookupType  => '',
        Repeated    => 0,
        @_,
    );

    unless ( $self->CurrentUser->HasRight(Object => $RT::System, Right => 'AdminCustomField') ) {
        return (0, $self->loc('Permission Denied'));
    }

    if ( $args{TypeComposite} ) {
        @args{'Type', 'MaxValues'} = split(/-/, $args{TypeComposite}, 2);
    }
    elsif ( $args{Type} =~ s/(?:(Single)|Multiple)$// ) {
        # old style Type string
        $args{'MaxValues'} = $1 ? 1 : 0;
    }
    
    if ( !exists $args{'Queue'}) {
    # do nothing -- things below are strictly backward compat
    }
    elsif (  ! $args{'Queue'} ) {
        unless ( $self->CurrentUser->HasRight( Object => $RT::System, Right => 'AssignCustomFields') ) {
            return ( 0, $self->loc('Permission Denied') );
        }
        $args{'LookupType'} = 'RT::Queue-RT::Ticket';
    }
    else {
        my $queue = RT::Queue->new($self->CurrentUser);
        $queue->Load($args{'Queue'});
        unless ($queue->Id) {
            return (0, $self->loc("Queue not found"));
        }
        unless ( $queue->CurrentUserHasRight('AssignCustomFields') ) {
            return ( 0, $self->loc('Permission Denied') );
        }
        $args{'LookupType'} = 'RT::Queue-RT::Ticket';
    }

    my ($ok, $msg) = $self->_IsValidRegex( $args{'Pattern'} );
    return (0, $self->loc("Invalid pattern: [_1]", $msg)) unless $ok;

    my $rv = $self->SUPER::Create(
        Name        => $args{'Name'},
        Type        => $args{'Type'},
        MaxValues   => $args{'MaxValues'},
        Pattern     => $args{'Pattern'},
        Description => $args{'Description'},
        Disabled    => $args{'Disabled'},
        LookupType  => $args{'LookupType'},
        Repeated    => $args{'Repeated'},
    );

    if ( exists $args{'ValuesClass'} ) {
        $self->SetValuesClass( $args{'ValuesClass'} );
    }

    return $rv unless exists $args{'Queue'};

    # Compat code -- create a new ObjectCustomField mapping
    my $OCF = RT::ObjectCustomField->new( $self->CurrentUser );
    $OCF->Create(
        CustomField => $self->Id,
        ObjectId => $args{'Queue'},
    );

    return $rv;
}

=head2 Load ID/NAME

Load a custom field.  If the value handed in is an integer, load by custom field ID. Otherwise, Load by name.

=cut

sub Load {
    my $self = shift;
    my $id = shift;

    if ( $id =~ /^\d+$/ ) {
        return $self->SUPER::Load( $id );
    } else {
        return $self->LoadByName( Name => $id );
    }
}


# {{{ sub LoadByName

=head2 LoadByName (Queue => QUEUEID, Name => NAME)

Loads the Custom field named NAME.

If a Queue parameter is specified, only look for ticket custom fields tied to that Queue.

If the Queue parameter is '0', look for global ticket custom fields.

If no queue parameter is specified, look for any and all custom fields with this name.

BUG/TODO, this won't let you specify that you only want user or group CFs.

=cut

# Compatibility for API change after 3.0 beta 1
*LoadNameAndQueue = \&LoadByName;
# Change after 3.4 beta.
*LoadByNameAndQueue = \&LoadByName;

sub LoadByName {
    my $self = shift;
    my %args = (
        Queue => undef,
        Name  => undef,
        @_,
    );

    # if we're looking for a queue by name, make it a number
    if ( defined $args{'Queue'} && $args{'Queue'} =~ /\D/ ) {
        my $QueueObj = RT::Queue->new( $self->CurrentUser );
        $QueueObj->Load( $args{'Queue'} );
        $args{'Queue'} = $QueueObj->Id;
    }

    # XXX - really naive implementation.  Slow. - not really. still just one query

    my $CFs = RT::CustomFields->new( $self->CurrentUser );
    $CFs->Limit( FIELD => 'Name', VALUE => $args{'Name'} );
    # Don't limit to queue if queue is 0.  Trying to do so breaks
    # RT::Group type CFs.
    if ( defined $args{'Queue'} ) {
        $CFs->LimitToQueue( $args{'Queue'} );
    }

    # When loading by name, it's ok if they're disabled. That's not a big deal.
    $CFs->{'find_disabled_rows'}=1;

    # We only want one entry.
    $CFs->RowsPerPage(1);
    return (0, $self->loc("Not found")) unless my $first = $CFs->First;
    return $self->LoadById( $first->id );
}

# }}}

# {{{ Dealing with custom field values 

=begin testing

use_ok(RT::CustomField);
ok(my $cf = RT::CustomField->new($RT::SystemUser));
ok(my ($id, $msg)=  $cf->Create( Name => 'TestingCF',
                                 Queue => '0',
                                 SortOrder => '1',
                                 Description => 'A Testing custom field',
                                 Type=> 'SelectSingle'), 'Created a global CustomField');
ok($id != 0, 'Global custom field correctly created');
ok ($cf->SingleValue);
is($cf->Type, 'Select');
is($cf->MaxValues, 1);

my ($val, $msg) = $cf->SetMaxValues('0');
ok($val, $msg);
is($cf->Type, 'Select');
is($cf->MaxValues, 0);
ok(!$cf->SingleValue );
ok(my ($bogus_val, $bogus_msg) = $cf->SetType('BogusType') , "Trying to set a custom field's type to a bogus type");
ok($bogus_val == 0, "Unable to set a custom field's type to a bogus type");

ok(my $bad_cf = RT::CustomField->new($RT::SystemUser));
ok(my ($bad_id, $bad_msg)=  $cf->Create( Name => 'TestingCF-bad',
                                 Queue => '0',
                                 SortOrder => '1',
                                 Description => 'A Testing custom field with a bogus Type',
                                 Type=> 'SelectSingleton'), 'Created a global CustomField with a bogus type');
ok($bad_id == 0, 'Global custom field correctly decided to not create a cf with a bogus type ');

=end testing

=cut

=head2 Custom field values

=head3 Values FIELD

Return a object (collection) of all acceptable values for this Custom Field.
Class of the object can vary and depends on the return value
of the C<ValuesClass> method.

=cut

*ValuesObj = \&Values;

sub Values {
    my $self = shift;

    my $class = $self->ValuesClass || 'RT::CustomFieldValues';
    eval "require $class" or die "$@";
    my $cf_values = $class->new( $self->CurrentUser );
    # if the user has no rights, return an empty object
    if ( $self->id && $self->CurrentUserHasRight( 'SeeCustomField') ) {
        $cf_values->LimitToCustomField( $self->Id );
    }
    return ($cf_values);
}

# {{{ AddValue

=head3 AddValue HASH

Create a new value for this CustomField.  Takes a paramhash containing the elements Name, Description and SortOrder

=begin testing

ok(my $cf = RT::CustomField->new($RT::SystemUser));
$cf->Load(1);
ok($cf->Id == 1);
ok(my ($val,$msg)  = $cf->AddValue(Name => 'foo' , Description => 'TestCFValue', SortOrder => '6'));
ok($val != 0);
ok (my ($delval, $delmsg) = $cf->DeleteValue($val));
ok ($delval,"Deleting a cf value: $delmsg");

=end testing

=cut

sub AddValue {
    my $self = shift;
    my %args = @_;

    unless ($self->CurrentUserHasRight('AdminCustomField')) {
        return (0, $self->loc('Permission Denied'));
    }

    # allow zero value
    if ( !defined $args{'Name'} || $args{'Name'} eq '' ) {
        return (0, $self->loc("Can't add a custom field value without a name"));
    }

    my $newval = RT::CustomFieldValue->new( $self->CurrentUser );
    return $newval->Create( %args, CustomField => $self->Id );
}


# }}}

# {{{ DeleteValue

=head3 DeleteValue ID

Deletes a value from this custom field by id.

Does not remove this value for any article which has had it selected

=cut

sub DeleteValue {
    my $self = shift;
    my $id = shift;
    unless ( $self->CurrentUserHasRight('AdminCustomField') ) {
        return (0, $self->loc('Permission Denied'));
    }

    my $val_to_del = RT::CustomFieldValue->new( $self->CurrentUser );
    $val_to_del->Load( $id );
    unless ( $val_to_del->Id ) {
        return (0, $self->loc("Couldn't find that value"));
    }
    unless ( $val_to_del->CustomField == $self->Id ) {
        return (0, $self->loc("That is not a value for this custom field"));
    }

    my $retval = $val_to_del->Delete;
    unless ( $retval ) {
        return (0, $self->loc("Custom field value could not be deleted"));
    }
    return ($retval, $self->loc("Custom field value deleted"));
}

# }}}


=head2 ValidateQueue Queue

Make sure that the queue specified is a valid queue name

=cut

sub ValidateQueue {
    my $self = shift;
    my $id = shift;

    return undef unless defined $id;
    # 0 means "Global" null would _not_ be ok.
    return 1 if $id eq '0';

    my $q = RT::Queue->new( $RT::SystemUser );
    $q->Load( $id );
    return undef unless $q->id;
    return 1;
}


# {{{ Types

=head2 Types 

Retuns an array of the types of CustomField that are supported

=cut

sub Types {
    return (keys %FieldTypes);
}

# }}}

# {{{ IsSelectionType
 
=head2 IsSelectionType 

Retuns a boolean value indicating whether the C<Values> method makes sense
to this Custom Field.

=cut

sub IsSelectionType {
    my $self = shift;
    my $type = @_? shift : $self->Type;
    return undef unless $type;

    $type =~ /(?:Select|Combobox|Autocomplete)/;
}

# }}}


=head2 IsExternalValues

=cut

sub IsExternalValues {
    my $self = shift;
    my $selectable = $self->IsSelectionType( @_ );
    return $selectable unless $selectable;

    my $class = $self->ValuesClass;
    return 0 if $class eq 'RT::CustomFieldValues';
    return 1;
}

sub ValuesClass {
    my $self = shift;
    return '' unless $self->IsSelectionType;

    my $class = $self->FirstAttribute( 'ValuesClass' );
    $class = $class->Content if $class;
    return $class || 'RT::CustomFieldValues';
}

sub SetValuesClass {
    my $self = shift;
    my $class = shift || 'RT::CustomFieldValues';

    if( $class eq 'RT::CustomFieldValues' ) {
        return $self->DeleteAttribute( 'ValuesClass' );
    }
    return $self->SetAttribute( Name => 'ValuesClass', Content => $class );
}


=head2 FriendlyType [TYPE, MAX_VALUES]

Returns a localized human-readable version of the custom field type.
If a custom field type is specified as the parameter, the friendly type for that type will be returned

=cut

sub FriendlyType {
    my $self = shift;

    my $type = @_ ? shift : $self->Type;
    my $max  = @_ ? shift : $self->MaxValues;

    if (my $friendly_type = $FieldTypes{$type}[$max>2 ? 2 : $max]) {
        return ( $self->loc( $friendly_type, $max ) );
    }
    else {
        return ( $self->loc( $type ) );
    }
}

sub FriendlyTypeComposite {
    my $self = shift;
    my $composite = shift || $self->TypeComposite;
    return $self->FriendlyType(split(/-/, $composite, 2));
}


=head2 ValidateType TYPE

Takes a single string. returns true if that string is a value
type of custom field

=begin testing

ok(my $cf = RT::CustomField->new($RT::SystemUser));
ok($cf->ValidateType('SelectSingle'));
ok($cf->ValidateType('SelectMultiple'));
ok(!$cf->ValidateType('SelectFooMultiple'));

=end testing

=cut

sub ValidateType {
    my $self = shift;
    my $type = shift;

    if ( $type =~ s/(?:Single|Multiple)$// ) {
        $RT::Logger->warning( "Prefix 'Single' and 'Multiple' to Type deprecated, use MaxValues instead at (". join(":",caller).")");
    }

    if ( $FieldTypes{$type} ) {
        return 1;
    }
    else {
        return undef;
    }
}


sub SetType {
    my $self = shift;
    my $type = shift;
    if ($type =~ s/(?:(Single)|Multiple)$//) {
        $RT::Logger->warning("'Single' and 'Multiple' on SetType deprecated, use SetMaxValues instead at (". join(":",caller).")");
        $self->SetMaxValues($1 ? 1 : 0);
    }
    $self->SUPER::SetType($type);
}

=head2 SetPattern STRING

Takes a single string representing a regular expression.  Performs basic
validation on that regex, and sets the C<Pattern> field for the CF if it
is valid.

=cut

sub SetPattern {
    my $self = shift;
    my $regex = shift;

    my ($ok, $msg) = $self->_IsValidRegex($regex);
    if ($ok) {
        return $self->SUPER::SetPattern($regex);
    }
    else {
        return (0, $self->loc("Invalid pattern: [_1]", $msg));
    }
}

=head2 _IsValidRegex(Str $regex) returns (Bool $success, Str $msg)

Tests if the string contains an invalid regex.

=cut

sub _IsValidRegex {
    my $self  = shift;
    my $regex = shift or return (1, 'valid');

    local $^W; local $@;
    local $SIG{__DIE__} = sub { 1 };
    local $SIG{__WARN__} = sub { 1 };

    if (eval { qr/$regex/; 1 }) {
        return (1, 'valid');
    }

    my $err = $@;
    $err =~ s{[,;].*}{};    # strip debug info from error
    chomp $err;
    return (0, $err);
}

# {{{ SingleValue

=head2 SingleValue

Returns true if this CustomField only accepts a single value. 
Returns false if it accepts multiple values

=cut

sub SingleValue {
    my $self = shift;
    if ($self->MaxValues == 1) {
        return 1;
    } 
    else {
        return undef;
    }
}

sub UnlimitedValues {
    my $self = shift;
    if ($self->MaxValues == 0) {
        return 1;
    } 
    else {
        return undef;
    }
}

# }}}

# {{{ sub CurrentUserHasRight

=head2 CurrentUserHasRight RIGHT

Helper function to call the custom field's queue's CurrentUserHasRight with the passed in args.

=cut

sub CurrentUserHasRight {
    my $self  = shift;
    my $right = shift;

    return $self->CurrentUser->HasRight(
        Object => $self,
        Right  => $right,
    );
}

# }}}

# {{{ sub _Set

sub _Set {
    my $self = shift;

    unless ( $self->CurrentUserHasRight('AdminCustomField') ) {
        return ( 0, $self->loc('Permission Denied') );
    }
    return $self->SUPER::_Set( @_ );

}

# }}}

# {{{ sub _Value 

=head2 _Value

Takes the name of a table column.
Returns its value as a string, if the user passes an ACL check

=cut

sub _Value {

    my $self  = shift;

    # we need to do the rights check
    unless ( $self->id && $self->CurrentUserHasRight('SeeCustomField') ) {
        return (undef);
    }
    return $self->__Value( @_ );
}

# }}}
# {{{ sub SetDisabled

=head2 SetDisabled

Takes a boolean.
1 will cause this custom field to no longer be avaialble for objects.
0 will re-enable this field.

=cut

# }}}

=head2 SetTypeComposite

Set this custom field's type and maximum values as a composite value


=cut

sub SetTypeComposite {
    my $self = shift;
    my $composite = shift;
    my ($type, $max_values) = split(/-/, $composite, 2);
    $self->SetType($type);
    $self->SetMaxValues($max_values);
}

=head2 SetLookupType

Autrijus: care to doc how LookupTypes work?

=cut

sub SetLookupType {
    my $self = shift;
    my $lookup = shift;
    if ( $lookup ne $self->LookupType ) {
        # Okay... We need to invalidate our existing relationships
        my $ObjectCustomFields = RT::ObjectCustomFields->new($self->CurrentUser);
        $ObjectCustomFields->LimitToCustomField($self->Id);
        $_->Delete foreach @{$ObjectCustomFields->ItemsArrayRef};
    }
    return $self->SUPER::SetLookupType($lookup);
}

=head2 TypeComposite

Returns a composite value composed of this object's type and maximum values

=cut


sub TypeComposite {
    my $self = shift;
    join('-', $self->Type, $self->MaxValues);
}

=head2 TypeComposites

Returns an array of all possible composite values for custom fields.

=cut

sub TypeComposites {
    my $self = shift;
    return grep !/(?:[Tt]ext|Combobox)-0/, map { ("$_-1", "$_-0") } $self->Types;
}

=head2 LookupTypes

Returns an array of LookupTypes available

=cut


sub LookupTypes {
    my $self = shift;
    return keys %FRIENDLY_OBJECT_TYPES;
}

my @FriendlyObjectTypes = (
    "[_1] objects",            # loc
    "[_1]'s [_2] objects",        # loc
    "[_1]'s [_2]'s [_3] objects",   # loc
);

=head2 FriendlyTypeLookup

=cut

sub FriendlyLookupType {
    my $self = shift;
    my $lookup = shift || $self->LookupType;
   
    return ($self->loc( $FRIENDLY_OBJECT_TYPES{$lookup} ))
                     if (defined  $FRIENDLY_OBJECT_TYPES{$lookup} );

    my @types = map { s/^RT::// ? $self->loc($_) : $_ }
      grep { defined and length }
      split( /-/, $lookup )
      or return;
    return ( $self->loc( $FriendlyObjectTypes[$#types], @types ) );
}


=head2 AddToObject OBJECT

Add this custom field as a custom field for a single object, such as a queue or group.

Takes an object 

=cut


sub AddToObject {
    my $self  = shift;
    my $object = shift;
    my $id = $object->Id || 0;

    unless (index($self->LookupType, ref($object)) == 0) {
        return ( 0, $self->loc('Lookup type mismatch') );
    }

    unless ( $object->CurrentUserHasRight('AssignCustomFields') ) {
        return ( 0, $self->loc('Permission Denied') );
    }

    my $ObjectCF = RT::ObjectCustomField->new( $self->CurrentUser );
    $ObjectCF->LoadByCols( ObjectId => $id, CustomField => $self->Id );
    if ( $ObjectCF->Id ) {
        return ( 0, $self->loc("That is already the current value") );
    }
    my ( $ret, $msg ) =
      $ObjectCF->Create( ObjectId => $id, CustomField => $self->Id );

    return ( $ret, $msg );
}


=head2 RemoveFromObject OBJECT

Remove this custom field  for a single object, such as a queue or group.

Takes an object 

=cut


sub RemoveFromObject {
    my $self = shift;
    my $object = shift;
    my $id = $object->Id || 0;

    unless (index($self->LookupType, ref($object)) == 0) {
        return ( 0, $self->loc('Object type mismatch') );
    }

    unless ( $object->CurrentUserHasRight('AssignCustomFields') ) {
        return ( 0, $self->loc('Permission Denied') );
    }

    my $ObjectCF = RT::ObjectCustomField->new( $self->CurrentUser );
    $ObjectCF->LoadByCols( ObjectId => $id, CustomField => $self->Id );
    unless ( $ObjectCF->Id ) {
        return ( 0, $self->loc("This custom field does not apply to that object") );
    }
    my ( $ret, $msg ) = $ObjectCF->Delete;

    return ( $ret, $msg );
}

# {{{ AddValueForObject

=head2 AddValueForObject HASH

Adds a custom field value for a record object of some kind. 
Takes a param hash of 

Required:

    Object
    Content

Optional:

    LargeContent
    ContentType

=cut

sub AddValueForObject {
    my $self = shift;
    my %args = (
        Object       => undef,
        Content      => undef,
        LargeContent => undef,
        ContentType  => undef,
        @_
    );
    my $obj = $args{'Object'} or return ( 0, $self->loc('Invalid object') );

    unless ( $self->CurrentUserHasRight('ModifyCustomField') ) {
        return ( 0, $self->loc('Permission Denied') );
    }

    unless ( $self->MatchPattern($args{'Content'}) ) {
        return ( 0, $self->loc('Input must match [_1]', $self->FriendlyPattern) );
    }

    $RT::Handle->BeginTransaction;

    if ( $self->MaxValues ) {
        my $current_values = $self->ValuesForObject($obj);
        my $extra_values = ( $current_values->Count + 1 ) - $self->MaxValues;

        # (The +1 is for the new value we're adding)

        # If we have a set of current values and we've gone over the maximum
        # allowed number of values, we'll need to delete some to make room.
        # which former values are blown away is not guaranteed

        while ($extra_values) {
            my $extra_item = $current_values->Next;
            unless ( $extra_item->id ) {
                $RT::Logger->crit( "We were just asked to delete "
                    ."a custom field value that doesn't exist!" );
                $RT::Handle->Rollback();
                return (undef);
            }
            $extra_item->Delete;
            $extra_values--;
        }
    }
    my $newval = RT::ObjectCustomFieldValue->new( $self->CurrentUser );
    my $val    = $newval->Create(
        ObjectType   => ref($obj),
        ObjectId     => $obj->Id,
        Content      => $args{'Content'},
        LargeContent => $args{'LargeContent'},
        ContentType  => $args{'ContentType'},
        CustomField  => $self->Id
    );

    unless ($val) {
        $RT::Handle->Rollback();
        return ($val, $self->loc("Couldn't create record"));
    }

    $RT::Handle->Commit();
    return ($val);

}

# }}}

# {{{ MatchPattern

=head2 MatchPattern STRING

Tests the incoming string against the Pattern of this custom field object
and returns a boolean; returns true if the Pattern is empty.

=cut

sub MatchPattern {
    my $self = shift;
    my $regex = $self->Pattern;

    return 1 unless length $regex;
    return ($_[0] =~ $regex);
}


# }}}

# {{{ FriendlyPattern

=head2 FriendlyPattern

Prettify the pattern of this custom field, by taking the text in C<(?#text)>
and localizing it.

=cut

sub FriendlyPattern {
    my $self = shift;
    my $regex = $self->Pattern;

    return '' unless length $regex;
    if ( $regex =~ /\(\?#([^)]*)\)/ ) {
        return '[' . $self->loc($1) . ']';
    }
    else {
        return $regex;
    }
}


# }}}

# {{{ DeleteValueForObject

=head2 DeleteValueForObject HASH

Deletes a custom field value for a ticket. Takes a param hash of Object and Content

Returns a tuple of (STATUS, MESSAGE). If the call succeeded, the STATUS is true. otherwise it's false

=cut

sub DeleteValueForObject {
    my $self = shift;
    my %args = ( Object => undef,
                 Content => undef,
                 Id => undef,
             @_ );


    unless ($self->CurrentUserHasRight('ModifyCustomField')) {
        return (0, $self->loc('Permission Denied'));
    }

    my $oldval = RT::ObjectCustomFieldValue->new($self->CurrentUser);

    if (my $id = $args{'Id'}) {
        $oldval->Load($id);
    }
    unless ($oldval->id) { 
        $oldval->LoadByObjectContentAndCustomField(
            Object => $args{'Object'}, 
            Content =>  $args{'Content'}, 
            CustomField => $self->Id,
        );
    }


    # check to make sure we found it
    unless ($oldval->Id) {
        return(0, $self->loc("Custom field value [_1] could not be found for custom field [_2]", $args{'Content'}, $self->Name));
    }

    # for single-value fields, we need to validate that empty string is a valid value for it
    if ( $self->SingleValue and not $self->MatchPattern( '' ) ) {
        return ( 0, $self->loc('Input must match [_1]', $self->FriendlyPattern) );
    }

    # delete it

    my $ret = $oldval->Delete();
    unless ($ret) {
        return(0, $self->loc("Custom field value could not be found"));
    }
    return($oldval->Id, $self->loc("Custom field value deleted"));
}


=head2 ValuesForObject OBJECT

Return an L<RT::ObjectCustomFieldValues> object containing all of this custom field's values for OBJECT 

=cut

sub ValuesForObject {
    my $self = shift;
    my $object = shift;

    my $values = new RT::ObjectCustomFieldValues($self->CurrentUser);
    unless ($self->CurrentUserHasRight('SeeCustomField')) {
        # Return an empty object if they have no rights to see
        return ($values);
    }
    
    
    $values->LimitToCustomField($self->Id);
    $values->LimitToEnabled();
    $values->LimitToObject($object);

    return ($values);
}


=head2 _ForObjectType PATH FRIENDLYNAME

Tell RT that a certain object accepts custom fields

Examples:

    'RT::Queue-RT::Ticket'                 => "Tickets",                # loc
    'RT::Queue-RT::Ticket-RT::Transaction' => "Ticket Transactions",    # loc
    'RT::User'                             => "Users",                  # loc
    'RT::Group'                            => "Groups",                 # loc

This is a class method. 

=cut

sub _ForObjectType {
    my $self = shift;
    my $path = shift;
    my $friendly_name = shift;

    $FRIENDLY_OBJECT_TYPES{$path} = $friendly_name;

}


=head2 IncludeContentForValue [VALUE] (and SetIncludeContentForValue)

Gets or sets the  C<IncludeContentForValue> for this custom field. RT
uses this field to automatically include content into the user's browser
as they display records with custom fields in RT.

=cut

sub SetIncludeContentForValue {
    shift->IncludeContentForValue(@_);
}
sub IncludeContentForValue{
    my $self = shift;
    $self->_URLTemplate('IncludeContentForValue', @_);
}



=head2 LinkValueTo [VALUE] (and SetLinkValueTo)

Gets or sets the  C<LinkValueTo> for this custom field. RT
uses this field to make custom field values into hyperlinks in the user's
browser as they display records with custom fields in RT.

=cut


sub SetLinkValueTo {
    shift->LinkValueTo(@_);
}

sub LinkValueTo {
    my $self = shift;
    $self->_URLTemplate('LinkValueTo', @_);

}


=head2 _URLTemplate  NAME [VALUE]

With one argument, returns the _URLTemplate named C<NAME>, but only if
the current user has the right to see this custom field.

With two arguments, attemptes to set the relevant template value.

=cut



sub _URLTemplate {
    my $self          = shift;
    my $template_name = shift;
    if (@_) {

        my $value = shift;
        unless ( $self->CurrentUserHasRight('AdminCustomField') ) {
            return ( 0, $self->loc('Permission Denied') );
        }
        $self->SetAttribute( Name => $template_name, Content => $value );
        return ( 1, $self->loc('Updated') );
    } else {
        unless ( $self->id && $self->CurrentUserHasRight('SeeCustomField') ) {
            return (undef);
        }

        my @attr = $self->Attributes->Named($template_name);
        my $attr = shift @attr;

        if ($attr) { return $attr->Content }

    }
}

1;
